import Foundation
import DriftlyCore

enum ReviewReplayCommand {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.dropFirst().contains("--replay-reviews")
    }

    static func runAndExit(arguments: [String]) {
        let options = Options(arguments: arguments)
        let exitCode = run(options: options)
        Foundation.exit(Int32(exitCode))
    }

    private static func run(options: Options) -> Int {
        let resultBox = ReplayResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            resultBox.value = await runAsync(options: options)
            semaphore.signal()
        }

        semaphore.wait()
        return options.strict ? resultBox.value : 0
    }

    private static func runAsync(options: Options) async -> Int {
        let store = SessionStore()
        let settings = store.loadCaptureSettings()
        let provider = AIProviderBridge.provider(for: settings.reviewProvider)

        if settings.reviewProvider == .ollama,
           settings.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fputs("No Ollama model is selected in Driftly settings.\n", stderr)
            return 1
        }

        let sessions = selectedSessions(from: store, options: options)
        guard !sessions.isEmpty else {
            fputs("No matching stored sessions were found.\n", stderr)
            return 1
        }
        var exitCode = 0

        for session in sessions {
            guard let detail = store.sessionDetail(id: session.id) else {
                fputs("Skipping \(session.id): missing session detail.\n", stderr)
                exitCode = 1
                continue
            }

            let events = store.events(between: detail.session.startedAt, and: detail.session.endedAt)
            printSessionHeader(detail.session, eventCount: events.count)
            printStoredReview(detail.review)

            do {
                let run = try await provider.generateReview(
                    settings: settings,
                    title: detail.session.goal,
                    personName: nil,
                    contextPattern: store.contextPatternSnapshot(goal: detail.session.goal, excludingSessionID: detail.session.id),
                    reviewLearnings: store.reviewLearningMemory()?.learnings ?? [],
                    feedbackExamples: store.promptReadyReviewFeedbackExamples(),
                    startedAt: detail.session.startedAt,
                    endedAt: detail.session.endedAt,
                    events: events,
                    segments: detail.segments
                )

                printRegeneratedReview(run.review)
                let warnings = replayWarnings(for: run.review)
                if warnings.isEmpty {
                    print("Checks: ok")
                } else {
                    exitCode = 1
                    print("Checks:")
                    for warning in warnings {
                        print("- \(warning)")
                    }
                }

                if options.showRaw {
                    print("")
                    print("Raw response:")
                    print(run.rawResponse)
                }
            } catch {
                exitCode = 1
                print("Regenerated review: failed")
                print("Error: \(error.localizedDescription)")
            }

            print("")
        }

        return exitCode
    }

    private static func selectedSessions(from store: SessionStore, options: Options) -> [StoredSession] {
        let sessions = store.sessionHistory(limit: max(options.limit, 1) * 4)

        if !options.sessionIDs.isEmpty {
            return sessions.filter { options.sessionIDs.contains($0.id) }
        }

        return Array(sessions.prefix(max(options.limit, 1)))
    }

    private static func printSessionHeader(_ session: StoredSession, eventCount: Int) {
        print("Session: \(session.goal)")
        print("ID: \(session.id)")
        print("Window: \(ActivityFormatting.sessionTime.string(from: session.startedAt, to: session.endedAt))")
        print("Stored status: \(session.reviewStatus.rawValue)")
        print("Captured events: \(eventCount)")
        print("")
    }

    private static func printStoredReview(_ review: StoredSessionReview?) {
        guard let review else {
            print("Stored review: none")
            print("")
            return
        }

        print("Stored review:")
        print("- Headline: \(review.review.headline)")
        print("- Summary: \(review.review.summary)")
        if let insight = review.review.reasons.first, !insight.isEmpty {
            print("- Insight: \(insight)")
        }
        print("")
    }

    private static func printRegeneratedReview(_ review: SessionReview) {
        print("Regenerated review:")
        print("- Headline: \(review.headline)")
        print("- Summary: \(review.summary)")
        if let insight = review.reasons.first, !insight.isEmpty {
            print("- Insight: \(insight)")
        }
    }

    private static func replayWarnings(for review: SessionReview) -> [String] {
        var warnings: [String] = []
        let summary = review.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let insight = review.reasons.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if summary.split(whereSeparator: \.isWhitespace).count > 45 {
            warnings.append("summary is longer than 45 words")
        }

        if insight.split(whereSeparator: \.isWhitespace).count > 18 {
            warnings.append("insight is longer than 18 words")
        }

        let lowercaseSummary = summary.lowercased()
        let lowercaseInsight = insight.lowercased()

        if lowercaseSummary.range(of: #"\b[a-z0-9-]+\.(com|be|so|app|io|ai|net|org)\b"#, options: .regularExpression) != nil {
            warnings.append("summary still contains a raw domain")
        }

        if (lowercaseSummary.contains("chrome") || lowercaseSummary.contains("safari")) &&
            ["youtube", "x", "github", "gmail", "notion", "google docs", "google drive"].contains(where: { lowercaseSummary.contains($0) }) {
            warnings.append("summary still mentions a browser shell even though a site is already named")
        }

        if summary.range(of: #"\b\d+%|\b\d+\s?(minute|minutes|second|seconds|m|s)\b"#, options: .regularExpression) == nil {
            warnings.append("summary is missing a concrete numeric fact")
        }

        if insight.isEmpty {
            warnings.append("insight is empty")
        }

        if lowercaseInsight.range(of: #"\b(before the next block|next block|stay focused|refocus|main goal)\b"#, options: .regularExpression) != nil {
            warnings.append("insight is still generic instead of immediate and actionable")
        }

        if !lowercaseInsight.contains(" and ") &&
            !lowercaseInsight.contains(" then ") &&
            !lowercaseInsight.contains(" before ") &&
            !lowercaseInsight.contains("start in ") &&
            !lowercaseInsight.contains("open ") {
            warnings.append("insight may be missing a replacement action")
        }

        if let dominantSurface = ["youtube", "x", "github", "gmail", "notion", "codex"].first(where: { lowercaseSummary.contains($0) }),
           !lowercaseInsight.contains(dominantSurface) {
            warnings.append("insight acts on a different surface than the summary")
        }

        return warnings
    }

    private struct Options {
        let limit: Int
        let sessionIDs: Set<String>
        let strict: Bool
        let showRaw: Bool

        init(arguments: [String]) {
            var remaining = arguments
            if let replayIndex = remaining.firstIndex(of: "--replay-reviews") {
                remaining.remove(at: replayIndex)
            }

            self.limit = Options.intValue(for: "--limit", in: remaining) ?? 6
            self.strict = remaining.contains("--strict")
            self.showRaw = remaining.contains("--raw")
            self.sessionIDs = Set(Options.values(for: "--session", in: remaining))
        }

        private static func intValue(for flag: String, in arguments: [String]) -> Int? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return Int(arguments[index + 1])
        }

        private static func values(for flag: String, in arguments: [String]) -> [String] {
            var values: [String] = []
            var index = 0
            while index < arguments.count {
                if arguments[index] == flag, arguments.indices.contains(index + 1) {
                    values.append(arguments[index + 1])
                    index += 2
                } else {
                    index += 1
                }
            }
            return values
        }
    }
}

private final class ReplayResultBox: @unchecked Sendable {
    var value = 0
}

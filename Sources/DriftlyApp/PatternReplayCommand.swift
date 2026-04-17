import Foundation
import DriftlyCore

enum PatternReplayCommand {
    static func shouldRun(arguments: [String]) -> Bool {
        arguments.dropFirst().contains("--replay-patterns")
    }

    static func runAndExit(arguments: [String]) {
        let options = Options(arguments: arguments)
        let exitCode = run(options: options)
        Foundation.exit(Int32(exitCode))
    }

    private static func run(options: Options) -> Int {
        let resultBox = PatternReplayResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            resultBox.value = await runAsync(options: options)
            semaphore.signal()
        }

        semaphore.wait()
        return resultBox.value
    }

    private static func runAsync(options: Options) async -> Int {
        let store = SessionStore()
        let settings = store.loadCaptureSettings()
        let provider = AIProviderBridge.provider(for: settings.reviewProvider)
        let sessions: [StoredSession]
        if let days = options.days {
            let periodEnd = Date()
            let periodStart = Calendar.current.date(byAdding: .day, value: -days, to: periodEnd) ?? periodEnd.addingTimeInterval(TimeInterval(-(days * 24 * 60 * 60)))
            sessions = store.sessions(overlapping: periodStart, and: periodEnd)
        } else {
            sessions = Array(store.sessionHistory(limit: max(options.limit, 1)).prefix(max(options.limit, 1)))
        }

        guard !sessions.isEmpty else {
            fputs("No saved sessions were found.\n", stderr)
            return 1
        }

        guard
            let periodStart = sessions.map(\.startedAt).min(),
            let periodEnd = sessions.map(\.endedAt).max()
        else {
            fputs("Could not determine the pattern window.\n", stderr)
            return 1
        }

        print("Pattern replay")
        print("Provider: \(settings.reviewProvider.displayName)")
        print("Kind: \(options.kind.rawValue)")
        print("Window: \(ActivityFormatting.sessionTime.string(from: periodStart, to: periodEnd))")
        print("Sessions: \(sessions.count)")
        print("")
        print("Input sessions:")
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let trimmedHeadline = session.headline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let headline = trimmedHeadline.isEmpty ? "No saved headline" : trimmedHeadline
            print("- \(ActivityFormatting.shortTime.string(from: session.startedAt)) | \(session.goal) | \(headline)")
        }
        print("")

        do {
            let summary = try await provider.generatePeriodicSummary(
                settings: settings,
                kind: options.kind,
                periodStart: periodStart,
                periodEnd: periodEnd,
                insightWritingSkill: DriftlyAgentContext.patternSkillName,
                sessions: sessions
            )

            print("Pattern output:")
            print("- Title: \(summary.title)")
            print("- Reflection: \(summary.summary)")
            return 0
        } catch {
            print("Pattern output: failed")
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }

    private struct Options {
        let limit: Int
        let kind: StoredPeriodicSummaryKind
        let days: Int?

        init(arguments: [String]) {
            var remaining = arguments
            if let index = remaining.firstIndex(of: "--replay-patterns") {
                remaining.remove(at: index)
            }

            limit = Options.intValue(for: "--limit", in: remaining) ?? 10
            kind = Options.kindValue(in: remaining) ?? .weekly
            days = Options.intValue(for: "--days", in: remaining)
        }

        private static func intValue(for flag: String, in arguments: [String]) -> Int? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return Int(arguments[index + 1])
        }

        private static func kindValue(in arguments: [String]) -> StoredPeriodicSummaryKind? {
            guard let index = arguments.firstIndex(of: "--kind"), arguments.indices.contains(index + 1) else {
                return nil
            }
            return StoredPeriodicSummaryKind(rawValue: arguments[index + 1].lowercased())
        }
    }
}

private final class PatternReplayResultBox: @unchecked Sendable {
    var value = 0
}

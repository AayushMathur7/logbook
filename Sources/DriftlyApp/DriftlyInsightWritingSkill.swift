import Foundation
import DriftlyCore

enum DriftlyInsightWritingSkill {
    private static let codeGoalHints = [
        "codex", "code", "repo", "build", "ship", "deploy", "github", "vercel", "app", "cursor"
    ]

    static func build(
        store: SessionStore,
        now: Date = Date(),
        excludingSessionID: String? = nil
    ) -> String? {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -5, to: now) ?? now.addingTimeInterval(-(5 * 24 * 60 * 60))

        let recentSessions = store.sessionHistory(limit: 40)
            .filter { session in
                session.startedAt >= cutoff && (excludingSessionID == nil || session.id != excludingSessionID)
            }

        let feedbackExamples = store.promptReadyReviewFeedbackExamples(limit: 4, maxPerPolarity: 2)
            .filter { excludingSessionID == nil || $0.sessionID != excludingSessionID }
        let learnings = store.reviewLearningMemory()?.learnings ?? []

        guard !recentSessions.isEmpty || !feedbackExamples.isEmpty || !learnings.isEmpty else {
            return nil
        }

        let workGoals = topCounts(recentSessions.map(\.goal), limit: 4)
        let labels = topCounts(recentSessions.flatMap(\.primaryLabels), limit: 6)
        let codeSessions = recentSessions.filter { looksLikeCodeGoal($0.goal) }
        let alignedHeadlines = topCounts(
            recentSessions.compactMap { session in
                guard session.verdict == .matched || session.verdict == .partiallyMatched else { return nil }
                guard let headline = session.headline, isUsableHistoricalPhrase(headline) else { return nil }
                return headline
            },
            limit: 4
        )
        let driftHeadlines = topCounts(
            recentSessions.compactMap { session in
                guard session.verdict == .missed else { return nil }
                guard let headline = session.headline, isUsableHistoricalPhrase(headline) else { return nil }
                return headline
            },
            limit: 4
        )

        let codeExamples = codeSessions
            .filter { session in
                let headline = session.headline ?? ""
                let summary = session.summary ?? ""
                return isUsableHistoricalPhrase(headline) && isUsableHistoricalPhrase(summary)
            }
            .prefix(4)
            .map { session in
                let headline = normalizeLegacyNaming(session.headline ?? "No saved headline")
                let summary = normalizeLegacyNaming(session.summary ?? "No saved summary")
                return "- Goal: \(normalizeLegacyNaming(session.goal)) | Headline: \(headline) | Summary: \(summary)"
            }
            .joined(separator: "\n")

        let badHistoricalPhrases = topCounts(
            recentSessions.flatMap { session -> [String] in
                [session.headline, session.summary]
                    .compactMap { phrase in
                        guard let phrase else { return nil }
                        return flaggedHistoricalPhrase(from: phrase)
                    }
            },
            limit: 8
        )

        let sessionExamples = recentSessions.prefix(6).map { session in
            let verdictLabel: String
            switch session.verdict {
            case .matched:
                verdictLabel = "strong match"
            case .partiallyMatched:
                verdictLabel = "partial match"
            case .missed:
                verdictLabel = "weak match"
            case nil:
                verdictLabel = session.reviewStatus.rawValue
            }

            let summary = session.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "No saved summary"
            let headline = session.headline?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "No saved headline"
            return "- Goal: \(normalizeLegacyNaming(session.goal)) | Verdict: \(verdictLabel) | Headline: \(normalizeLegacyNaming(headline)) | Summary: \(normalizeLegacyNaming(summary))"
        }.joined(separator: "\n")

        let feedbackLines = feedbackExamples.map { example in
            "- \(example.label.rawValue): For \"\(normalizeLegacyNaming(example.goal))\", the user said \(normalizeLegacyNaming(example.userFeedback))"
        }.joined(separator: "\n")

        return """
        # Recent Driftly patterns

        Generated from Driftly's recent local history.

        ## How to use this

        - This is soft personalization only. Current session facts always win.
        - Use it to sharpen wording, pattern recognition, and next-step quality.
        - Never mention this file, hidden memory, feedback machinery, or prior sessions in the final output.
        - Avoid repeating stale labels if the current evidence points somewhere else.

        ## Pattern window

        - Sessions considered: \(recentSessions.count)

        ### Common goals

        \(workGoals.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ### Repeated labels

        \(labels.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ### Recent aligned headlines

        \(alignedHeadlines.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ### Recent drift headlines

        \(driftHeadlines.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ### Recent code-session examples worth copying

        \(codeExamples.nilIfBlank ?? "- none")

        ### Old Driftly phrasing to avoid

        \(badHistoricalPhrases.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ## Writing preferences learned from feedback

        \(learnings.prefix(5).map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        ## Recent feedback examples

        \(feedbackLines.nilIfBlank ?? "- none")

        ## Recent session examples

        \(sessionExamples.nilIfBlank ?? "- none")
        """
    }

    private static func topCounts(_ values: [String], limit: Int) -> [String] {
        Dictionary(
            values.map { (normalizeLegacyNaming($0).trimmingCharacters(in: .whitespacesAndNewlines), 1) },
            uniquingKeysWith: +
        )
            .filter { !$0.key.isEmpty }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map { entry in
                entry.value > 1 ? "\(entry.key) (\(entry.value)x)" : entry.key
            }
    }

    private static func normalizeLegacyNaming(_ value: String) -> String {
        value
            .replacingOccurrences(of: "Log Book", with: "Driftly")
            .replacingOccurrences(of: "LogBook", with: "Driftly")
            .replacingOccurrences(of: "Logbook", with: "Driftly")
    }

    private static func looksLikeCodeGoal(_ goal: String) -> Bool {
        let normalized = goal.lowercased()
        return codeGoalHints.contains { normalized.contains($0) }
    }

    private static func isUsableHistoricalPhrase(_ value: String) -> Bool {
        flaggedHistoricalPhrase(from: value) == nil
    }

    private static func flaggedHistoricalPhrase(from value: String) -> String? {
        let normalized = normalizeLegacyNaming(value).trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()
        guard !normalized.isEmpty else { return nil }

        let bannedFragments = [
            "you got pulled into",
            "dominated your time block",
            "consumed your focus time",
            "desktop activity didn't align",
            "partially matched the building goal",
            "watched youtube videos and used codex",
            "drifted into passive media viewing",
            "your block largely missed the goal",
            "work tools shared time with youtube distraction",
            "session consumed from",
            "you spent the session",
            "fragmented repo orientation",
            "aligned research exploration",
            "productivity optimization"
        ]

        guard bannedFragments.contains(where: { lowercased.contains($0) }) else {
            return nil
        }

        return normalized
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

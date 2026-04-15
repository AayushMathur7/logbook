import Foundation
import DriftlyCore

struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

enum DriftlySelfTest {
    static func run() {
        let tests: [(String, () throws -> Void)] = [
            ("privacy excludes by bundle ID", testPrivacyExcludeBundleID),
            ("privacy excludes by domain", testPrivacyExcludeDomain),
            ("privacy excludes by path prefix", testPrivacyExcludePath),
            ("privacy redacts window titles", testPrivacyRedactsWindowTitles),
            ("privacy summary-only strips full URL", testPrivacySummaryOnlyDomains),
            ("sessionizer splits on idle boundary", testSessionizerIdleBoundary),
            ("sessionizer groups by browser domain continuity", testSessionizerDomainContinuity),
            ("sessionizer ignores pause resume as work events", testSessionizerIgnoresPauseResume),
            ("timeline derives GitHub repo labels", testTimelineDerivesGitHubRepoLabels),
            ("timeline derives YouTube and X entities", testTimelineDerivesSocialEntities),
            ("timeline derives Notion Calendar entities", testTimelineDerivesNotionCalendarEntity),
            ("timeline classifies Spotify as media", testTimelineClassifiesSpotifyAsMedia),
            ("observability classifies goal-aligned coding as direct work", testObservabilityClassifiesDirectWork),
            ("observability separates support and drift", testObservabilitySeparatesSupportAndDrift),
            ("observability treats goal-matched youtube as direct", testObservabilityTreatsGoalMatchedYouTubeAsDirect),
            ("attention deriver attaches spotify as overlay", testAttentionDeriverAttachesSpotifyOverlay),
            ("timeline merges adjacent matching events", testTimelineMergesMatchingEvents),
            ("timeline infers file context from editor titles", testTimelineInfersEditorFileContext),
            ("timeline strips browser chrome from generic titles", testTimelineCleansBrowserTitles),
            ("review feedback overwrites and keeps snapshots", testReviewFeedbackOverwriteAndSnapshots),
            ("prompt-ready feedback examples filter noise", testPromptReadyFeedbackExampleFiltering),
            ("review learning memory round trips", testReviewLearningMemoryRoundTrip),
            ("context graph stores session surfaces and transitions", testContextGraphStoresSessionSurfacesAndTransitions),
            ("context graph derives recent pattern snapshot", testContextGraphDerivesPriorPatternSnapshot),
            ("path noise filter drops macOS temp churn", testPathNoiseFilterDropsTempChurn),
            ("focus guard waits five minutes before nudging", testFocusGuardWaitsBeforePrompting),
            ("focus guard stays quiet when idle or near session end", testFocusGuardSkipsIdleAndNearEnd),
            ("focus guard needs ninety seconds of continuous drift", testFocusGuardRequiresContinuousDrift),
            ("focus guard keeps ambiguous sessions unclear", testFocusGuardKeepsAmbiguousSessionsQuiet),
            ("focus guard catches dominant drift even with nearby work", testFocusGuardCatchesDominantDrift),
            ("focus guard respects cooldowns", testFocusGuardRespectsCooldown),
            ("focus guard caps prompts per session", testFocusGuardCapsSessionPrompts),
            ("focus guard preset scales prompt caps by session length", testFocusGuardPresetScalesPromptCaps),
            ("focus guard snooze suppresses prompts", testFocusGuardSnoozeSuppressesPrompt),
            ("focus guard records recovery when work resumes", testFocusGuardRecordsRecovery),
            ("focus guard review summary includes prompt facts", testFocusGuardReviewSummaryIncludesFacts),
            ("focus guard disabled never prompts", testFocusGuardDisabledNeverPrompts),
        ]

        let startedAt = Date()
        var passed = 0
        var failed: [(String, String)] = []

        for (name, test) in tests {
            do {
                try test()
                passed += 1
                print("PASS  \(name)")
            } catch {
                failed.append((name, String(describing: error)))
                print("FAIL  \(name)")
                print("      \(error)")
            }
        }

        let duration = Date().timeIntervalSince(startedAt)
        print("")
        print("Self-test analytics")
        print("  total: \(tests.count)")
        print("  passed: \(passed)")
        print("  failed: \(failed.count)")
        print("  duration_ms: \(Int((duration * 1000).rounded()))")

        if !failed.isEmpty {
            print("")
            print("Failures")
            for (name, message) in failed {
                print("  - \(name): \(message)")
            }
            Foundation.exit(1)
        }
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SelfTestFailure(description: message)
        }
    }

    static func testPrivacyExcludeBundleID() throws {
        let settings = CaptureSettings(excludedAppBundleIDs: ["com.secret.app"])
        let event = ActivityEvent(
            occurredAt: Date(),
            source: .workspace,
            kind: .appActivated,
            bundleID: "com.secret.app"
        )

        try require(PrivacyFilter.apply(to: event, settings: settings) == nil, "expected event to be dropped")
    }

    static func testPrivacyExcludeDomain() throws {
        let settings = CaptureSettings(excludedDomains: ["private.example.com"])
        let event = ActivityEvent(
            occurredAt: Date(),
            source: .browser,
            kind: .tabFocused,
            resourceURL: "https://private.example.com/report",
            domain: "private.example.com"
        )

        try require(PrivacyFilter.apply(to: event, settings: settings) == nil, "expected browser event to be dropped")
    }

    static func testPrivacyExcludePath() throws {
        let settings = CaptureSettings(excludedPathPrefixes: ["/Users/aayush/Secret"])
        let event = ActivityEvent(
            occurredAt: Date(),
            source: .fileSystem,
            kind: .fileModified,
            path: "/Users/aayush/Secret/plan.txt"
        )

        try require(PrivacyFilter.apply(to: event, settings: settings) == nil, "expected file event to be dropped")
    }

    static func testPrivacyRedactsWindowTitles() throws {
        let settings = CaptureSettings(redactedTitleBundleIDs: ["com.chat.app"])
        let event = ActivityEvent(
            occurredAt: Date(),
            source: .workspace,
            kind: .appActivated,
            bundleID: "com.chat.app",
            windowTitle: "Sensitive thread",
            resourceTitle: "Visible resource"
        )

        let filtered = PrivacyFilter.apply(to: event, settings: settings)
        try require(filtered?.windowTitle == nil, "expected window title to be redacted")
        try require(filtered?.resourceTitle == "Visible resource", "expected resource title to remain")
    }

    static func testPrivacySummaryOnlyDomains() throws {
        let settings = CaptureSettings(summaryOnlyDomains: ["github.com"])
        let event = ActivityEvent(
            occurredAt: Date(),
            source: .browser,
            kind: .tabChanged,
            resourceTitle: "AayushMathur7/driftly pull request",
            resourceURL: "https://github.com/AayushMathur7/driftly/pull/42",
            domain: "github.com"
        )

        let filtered = PrivacyFilter.apply(to: event, settings: settings)
        try require(filtered?.domain == "github.com", "expected domain to survive")
        try require(filtered?.resourceTitle == "github.com", "expected title to collapse to domain")
        try require(filtered?.resourceURL == nil, "expected full URL to be removed")
    }

    static func testSessionizerIdleBoundary() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                id: "1",
                occurredAt: now,
                source: .workspace,
                kind: .appActivated,
                appName: "Cursor",
                bundleID: "com.cursor.app",
                windowTitle: "Driftly"
            ),
            ActivityEvent(
                id: "2",
                occurredAt: now.addingTimeInterval(60),
                source: .presence,
                kind: .userIdle
            ),
            ActivityEvent(
                id: "3",
                occurredAt: now.addingTimeInterval(120),
                source: .presence,
                kind: .userResumed
            ),
            ActivityEvent(
                id: "4",
                occurredAt: now.addingTimeInterval(180),
                source: .workspace,
                kind: .appActivated,
                appName: "Cursor",
                bundleID: "com.cursor.app",
                windowTitle: "Driftly"
            ),
        ]

        let sessions = Sessionizer.sessions(from: events)
        try require(sessions.count == 2, "expected 2 sessions, got \(sessions.count)")
    }

    static func testSessionizerDomainContinuity() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                id: "1",
                occurredAt: now,
                source: .browser,
                kind: .tabFocused,
                appName: "Safari",
                bundleID: "com.apple.Safari",
                resourceTitle: "Search results",
                resourceURL: "https://example.com/a",
                domain: "example.com"
            ),
            ActivityEvent(
                id: "2",
                occurredAt: now.addingTimeInterval(60),
                source: .browser,
                kind: .tabChanged,
                appName: "Safari",
                bundleID: "com.apple.Safari",
                resourceTitle: "Second page",
                resourceURL: "https://example.com/b",
                domain: "example.com"
            ),
            ActivityEvent(
                id: "3",
                occurredAt: now.addingTimeInterval(120),
                source: .browser,
                kind: .tabChanged,
                appName: "Safari",
                bundleID: "com.apple.Safari",
                resourceTitle: "Different site",
                resourceURL: "https://other.example.net/c",
                domain: "other.example.net"
            ),
        ]

        let sessions = Sessionizer.sessions(from: events)
        try require(sessions.count == 2, "expected 2 sessions, got \(sessions.count)")
        try require(sessions[0].eventCount == 2, "expected first session to keep same-domain events together")
        try require(sessions[1].contextLabel == "Different site", "expected second session label to come from resource title")
    }

    static func testSessionizerIgnoresPauseResume() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                id: "1",
                occurredAt: now,
                source: .workspace,
                kind: .appActivated,
                appName: "Terminal",
                bundleID: "com.apple.Terminal"
            ),
            ActivityEvent(
                id: "2",
                occurredAt: now.addingTimeInterval(10),
                source: .system,
                kind: .capturePaused
            ),
            ActivityEvent(
                id: "3",
                occurredAt: now.addingTimeInterval(20),
                source: .system,
                kind: .captureResumed
            ),
            ActivityEvent(
                id: "4",
                occurredAt: now.addingTimeInterval(30),
                source: .shell,
                kind: .commandFinished,
                appName: "Terminal",
                bundleID: "com.apple.Terminal",
                command: "swift test",
                workingDirectory: "/Users/aayush/ai-projects/driftly"
            ),
        ]

        let sessions = Sessionizer.sessions(from: events)
        try require(sessions.count == 2, "expected 2 sessions, got \(sessions.count)")
        try require(sessions[1].commands == ["swift test"], "expected command session to retain command payload")
    }

    static func testTimelineDerivesGitHubRepoLabels() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .browser,
                kind: .tabFocused,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "AayushMathur7/driftly pull request",
                resourceURL: "https://github.com/AayushMathur7/driftly/pull/42",
                domain: "github.com"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one GitHub segment")
        try require(segments[0].primaryLabel == "GitHub", "expected GitHub primary label")
        try require(segments[0].secondaryLabel == "AayushMathur7/driftly PR #42", "expected PR label")
        try require(segments[0].repoName == "driftly", "expected repo name")
        try require(segments[0].category == .coding, "expected coding category")
    }

    static func testTimelineDerivesSocialEntities() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .browser,
                kind: .tabFocused,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "Some video title",
                resourceURL: "https://www.youtube.com/shorts/abc123",
                domain: "youtube.com"
            ),
            ActivityEvent(
                occurredAt: now.addingTimeInterval(180),
                source: .browser,
                kind: .tabChanged,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "Home / X",
                resourceURL: "https://x.com/home",
                domain: "x.com"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(240))
        try require(segments.count == 2, "expected two social/media segments")
        try require(segments[0].primaryLabel == "YouTube Shorts", "expected shorts label")
        try require(segments[0].category == .media, "expected media category")
        try require(segments[1].primaryLabel == "X", "expected X label")
        try require(segments[1].secondaryLabel == "Home feed", "expected home feed label")
        try require(segments[1].category == .social, "expected social category")
    }

    static func testTimelineDerivesNotionCalendarEntity() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .browser,
                kind: .tabFocused,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "Apr 12–18, 2026 · Notion Calendar",
                resourceURL: "https://calendar.notion.so/day",
                domain: "calendar.notion.so"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one calendar segment")
        try require(segments[0].primaryLabel == "Notion Calendar", "expected Notion Calendar primary label")
        try require(segments[0].domain == "calendar.notion.so", "expected normalized calendar domain")
    }

    static func testTimelineClassifiesSpotifyAsMedia() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .workspace,
                kind: .appActivated,
                appName: "Spotify",
                bundleID: "com.spotify.client",
                windowTitle: "Lana Del Rey - Candy Necklace (feat. Jon Batiste)"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one spotify segment")
        try require(segments[0].category == .media, "expected spotify to classify as media")
        try require(segments[0].primaryLabel.contains("Candy Necklace"), "expected visible track title to survive")
    }

    static func testObservabilityClassifiesDirectWork() throws {
        let now = Date()
        let segments = [
            TimelineSegment(
                startAt: now,
                endAt: now.addingTimeInterval(240),
                appName: "Cursor",
                primaryLabel: "driftly",
                secondaryLabel: "Sources/DriftlyApp/ContentView.swift",
                category: .coding,
                repoName: "driftly",
                filePath: "/Users/aayush/ai-projects/driftly/Sources/DriftlyApp/ContentView.swift",
                confidence: 0.9,
                eventCount: 3
            ),
        ]

        let observed = TimelineDeriver.observeSegments(segments, goal: "Work on Driftly timeline UI")
        let summary = TimelineDeriver.summarizeObservedSegments(observed)

        try require(observed.count == 1, "expected one observed segment")
        try require(observed[0].role == .direct, "expected direct role for goal-aligned file editing")
        try require(observed[0].goalRelevance >= 0.45, "expected strong relevance for driftly file editing")
        try require(summary.goalProgressEstimate == .strong || summary.goalProgressEstimate == .partial, "expected non-zero progress estimate")
    }

    static func testObservabilitySeparatesSupportAndDrift() throws {
        let now = Date()
        let segments = [
            TimelineSegment(
                startAt: now,
                endAt: now.addingTimeInterval(120),
                appName: "Google Chrome",
                primaryLabel: "GitHub",
                secondaryLabel: "AayushMathur7/driftly PR #42",
                category: .coding,
                repoName: "driftly",
                url: "https://github.com/AayushMathur7/driftly/pull/42",
                domain: "github.com",
                confidence: 0.95,
                eventCount: 2
            ),
            TimelineSegment(
                startAt: now.addingTimeInterval(120),
                endAt: now.addingTimeInterval(240),
                appName: "Google Chrome",
                primaryLabel: "YouTube Watch",
                secondaryLabel: "sidemen clip",
                category: .media,
                url: "https://youtube.com/watch?v=abc",
                domain: "youtube.com",
                confidence: 0.95,
                eventCount: 1
            ),
        ]

        let observed = TimelineDeriver.observeSegments(segments, goal: "Work on Driftly timeline UI")
        let summary = TimelineDeriver.summarizeObservedSegments(observed)

        try require(observed.count == 2, "expected two observed segments")
        try require(observed[0].role == .support, "expected GitHub browser review to count as support work")
        try require(observed[1].role == .drift, "expected YouTube to count as drift")
        try require(summary.supportSeconds > 0, "expected support seconds to accumulate")
        try require(summary.driftSeconds > 0, "expected drift seconds to accumulate")
        try require(summary.driftInterruptions >= 1, "expected drift interruption after support work")
    }

    static func testObservabilityTreatsGoalMatchedYouTubeAsDirect() throws {
        let now = Date()
        let segments = [
            TimelineSegment(
                startAt: now,
                endAt: now.addingTimeInterval(480),
                appName: "Google Chrome",
                primaryLabel: "YouTube Watch",
                secondaryLabel: "Bill Gurley interview",
                category: .media,
                url: "https://www.youtube.com/watch?v=abc",
                domain: "youtube.com",
                confidence: 0.95,
                eventCount: 4
            ),
            TimelineSegment(
                startAt: now.addingTimeInterval(480),
                endAt: now.addingTimeInterval(540),
                appName: "Google Chrome",
                primaryLabel: "X",
                secondaryLabel: "Home feed",
                category: .social,
                url: "https://x.com/home",
                domain: "x.com",
                confidence: 0.95,
                eventCount: 2
            ),
        ]

        let observed = TimelineDeriver.observeSegments(segments, goal: "I wanna just watch YouTube")
        let summary = TimelineDeriver.summarizeObservedSegments(observed)

        try require(observed[0].role == .direct, "expected youtube watch page to align with explicit watch youtube goal")
        try require(observed[1].role == .drift, "expected x detour to remain drift for watch youtube goal")
        try require(summary.goalProgressEstimate == .strong || summary.goalProgressEstimate == .partial, "expected non-zero progress estimate for matched youtube session")
    }

    static func testAttentionDeriverAttachesSpotifyOverlay() throws {
        let now = Date()
        let segments = [
            TimelineSegment(
                startAt: now,
                endAt: now.addingTimeInterval(60),
                appName: "Google Chrome",
                primaryLabel: "GitHub",
                secondaryLabel: "AayushMathur7/driftly PR #42",
                category: .coding,
                repoName: "driftly",
                domain: "github.com",
                confidence: 0.95,
                eventCount: 1
            ),
            TimelineSegment(
                startAt: now.addingTimeInterval(70),
                endAt: now.addingTimeInterval(140),
                appName: "Spotify",
                primaryLabel: "Lana Del Rey - Candy Necklace (feat. Jon Batiste)",
                category: .media,
                confidence: 0.8,
                eventCount: 1
            ),
            TimelineSegment(
                startAt: now.addingTimeInterval(150),
                endAt: now.addingTimeInterval(240),
                appName: "Google Chrome",
                primaryLabel: "X",
                secondaryLabel: "Home feed",
                category: .social,
                domain: "x.com",
                confidence: 0.95,
                eventCount: 1
            ),
        ]

        let attention = AttentionDeriver.derive(from: segments)
        try require(attention.count == 2, "expected spotify overlay to avoid becoming its own attention segment")
        try require(attention[0].overlays.count == 1, "expected first attention segment to receive spotify overlay")
        try require(attention[0].overlays[0].kind == .audio, "expected overlay to be audio")
    }

    static func testTimelineMergesMatchingEvents() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .browser,
                kind: .tabFocused,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "AayushMathur7/driftly pull request",
                resourceURL: "https://github.com/AayushMathur7/driftly/pull/42",
                domain: "github.com"
            ),
            ActivityEvent(
                occurredAt: now.addingTimeInterval(60),
                source: .browser,
                kind: .tabChanged,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "AayushMathur7/driftly pull request",
                resourceURL: "https://github.com/AayushMathur7/driftly/pull/42",
                domain: "github.com"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(120))
        try require(segments.count == 1, "expected matching events to merge into one segment")
        try require(segments[0].eventCount == 2, "expected merged segment event count to be 2")
    }

    static func testTimelineInfersEditorFileContext() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .workspace,
                kind: .appActivated,
                appName: "Cursor",
                bundleID: "com.todesktop.230313mzl4w4u92",
                windowTitle: "ActivityMonitor.swift — driftly — Untracked"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one editor segment")
        try require(segments[0].primaryLabel == "driftly", "expected repo label from editor title")
        try require(segments[0].secondaryLabel == "ActivityMonitor.swift", "expected file label from editor title")
        try require(segments[0].repoName == "driftly", "expected repo name to be inferred")
        try require(segments[0].filePath == "ActivityMonitor.swift", "expected lightweight file path to be captured")
    }

    static func testTimelineCleansBrowserTitles() throws {
        let now = Date()
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .workspace,
                kind: .appActivated,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                windowTitle: "New tab - Google Chrome – Aayush"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one browser segment")
        try require(segments[0].primaryLabel == "New tab", "expected browser chrome suffix to be stripped")
    }

    static func testReviewFeedbackOverwriteAndSnapshots() throws {
        let store = makeTemporaryStore()
        let sessionID = "session-feedback-overwrite"
        try seedSession(store: store, sessionID: sessionID, goal: "Ship settings UI")

        try store.saveReviewFeedback(
            SessionReviewFeedback(
                sessionID: sessionID,
                wasHelpful: false,
                note: "Mention that GitHub auth did happen.",
                goalSnapshot: "Ship settings UI",
                reviewHeadlineSnapshot: "YouTube won",
                reviewSummarySnapshot: "You watched YouTube instead of shipping the UI.",
                reviewTakeawaySnapshot: "The task never really started."
            )
        )

        try store.saveReviewFeedback(
            SessionReviewFeedback(
                sessionID: sessionID,
                wasHelpful: true,
                note: "This version is much closer to what happened.",
                goalSnapshot: "Ship settings UI",
                reviewHeadlineSnapshot: "GitHub showed up, but YouTube won.",
                reviewSummarySnapshot: "You reached GitHub briefly, then drifted back to YouTube.",
                reviewTakeawaySnapshot: "You touched the task, but it stayed brief."
            )
        )

        let saved = store.reviewFeedback(sessionID: sessionID)
        try require(saved != nil, "expected saved feedback")
        try require(saved?.wasHelpful == true, "expected latest feedback to overwrite prior value")
        try require(saved?.reviewHeadlineSnapshot == "GitHub showed up, but YouTube won.", "expected latest headline snapshot")
        try require(saved?.reviewTakeawaySnapshot == "You touched the task, but it stayed brief.", "expected latest takeaway snapshot")
    }

    static func testPromptReadyFeedbackExampleFiltering() throws {
        let store = makeTemporaryStore()

        try seedFeedback(
            store: store,
            sessionID: "s1",
            helpful: false,
            note: "Mention that GitHub auth happened even if it was brief.",
            goal: "deploy driftly to github",
            headline: "GitHub showed up, but YouTube won.",
            summary: "You reached GitHub, but YouTube still took more of the block."
        )
        try seedFeedback(
            store: store,
            sessionID: "s2",
            helpful: true,
            note: "This was right. Watching YouTube was the actual goal.",
            goal: "I wanna just watch YouTube",
            headline: "YouTube stayed front and center.",
            summary: "You spent most of the block on YouTube."
        )
        try seedFeedback(
            store: store,
            sessionID: "s3",
            helpful: false,
            note: "wrong",
            goal: "work on ui",
            headline: "Neutral activity dominated this block.",
            summary: "You moved between apps without a clear thread."
        )
        try seedFeedback(
            store: store,
            sessionID: "s4",
            helpful: false,
            note: "Mention that GitHub auth happened even if it was brief.",
            goal: "deploy driftly to github",
            headline: "GitHub was invisible.",
            summary: "The review missed the GitHub step."
        )
        try seedFeedback(
            store: store,
            sessionID: "s5",
            helpful: true,
            note: "Good call on treating Spotify as background.",
            goal: "Help me get my day ready",
            headline: "Setup time got split with music.",
            summary: "Spotify was visible during the block."
        )

        let examples = store.promptReadyReviewFeedbackExamples()
        try require(examples.count == 3, "expected 3 prompt-ready examples after filtering noise and duplicates, got \(examples.count)")
        try require(examples.contains(where: { $0.label == .confirmed }), "expected at least one confirmed example")
        try require(examples.contains(where: { $0.label == .correction }), "expected at least one correction example")
        try require(!examples.contains(where: { $0.userFeedback.lowercased() == "wrong" }), "expected noisy short feedback to be removed")
    }

    static func testReviewLearningMemoryRoundTrip() throws {
        let store = makeTemporaryStore()
        let memory = SessionReviewLearningMemory(
            sourceFeedbackCount: 4,
            learnings: [
                "When the goal is intentional watching, do not frame YouTube as drift by default.",
                "If GitHub auth or repo steps happened, mention them even when they were brief.",
            ]
        )

        try store.saveReviewLearningMemory(memory)
        let loaded = store.reviewLearningMemory()

        try require(loaded != nil, "expected saved learning memory")
        try require(loaded?.sourceFeedbackCount == 4, "expected source feedback count to round trip")
        try require(loaded?.learnings.count == 2, "expected learnings to round trip")
        try require(loaded?.learnings.first?.contains("YouTube") == true, "expected first learning to persist")
    }

    static func testContextGraphStoresSessionSurfacesAndTransitions() throws {
        let store = makeTemporaryStore()
        let startedAt = Date(timeIntervalSince1970: 10_000)
        let events = [
            ActivityEvent(
                occurredAt: startedAt,
                source: .workspace,
                kind: .appActivated,
                appName: "Codex",
                bundleID: "com.openai.codex",
                windowTitle: "settings migration"
            ),
            makeGitHubSupportEvent(at: startedAt.addingTimeInterval(60)),
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(120)),
        ]
        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: startedAt.addingTimeInterval(180))

        try store.saveSession(
            StoredSession(
                id: "context-1",
                goal: "ship the settings migration",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(180),
                reviewStatus: .ready,
                primaryLabels: TimelineDeriver.primaryLabels(from: segments)
            ),
            review: nil,
            segments: segments,
            rawEventCount: events.count
        )

        let db = SessionStore(path: URL(fileURLWithPath: store.databasePath))
        let snapshot = db.contextPatternSnapshot(goal: "ship the settings migration")
        try require(snapshot != nil, "expected context pattern snapshot to exist")
        try require(snapshot?.alignedSurfaces.contains(where: { $0.localizedCaseInsensitiveContains("Codex") || $0.localizedCaseInsensitiveContains("driftly") || $0.localizedCaseInsensitiveContains("GitHub") }) == true, "expected aligned surfaces to include work tools")
        try require(snapshot?.driftSurfaces.contains(where: { $0.contains("YouTube") }) == true, "expected drift surfaces to include YouTube")
        try require(snapshot?.commonTransitions.isEmpty == false, "expected at least one stored transition")
    }

    static func testContextGraphDerivesPriorPatternSnapshot() throws {
        let store = makeTemporaryStore()
        let startedAt = Date(timeIntervalSince1970: 20_000)

        let sessionOneEvents = [
            ActivityEvent(
                id: "pattern-1-0",
                occurredAt: startedAt,
                source: .workspace,
                kind: .appActivated,
                appName: "Codex",
                bundleID: "com.openai.codex",
                windowTitle: "settings migration"
            ),
            makeGitHubSupportEvent(at: startedAt.addingTimeInterval(60)),
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(120)),
        ]
        let sessionOneSegments = TimelineDeriver.deriveSegments(from: sessionOneEvents, sessionEnd: startedAt.addingTimeInterval(180))
        try store.saveSession(
            StoredSession(
                id: "pattern-1",
                goal: "ship the settings migration",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(180),
                reviewStatus: .ready,
                primaryLabels: TimelineDeriver.primaryLabels(from: sessionOneSegments)
            ),
            review: nil,
            segments: sessionOneSegments,
            rawEventCount: sessionOneEvents.count
        )

        let sessionTwoStart = startedAt.addingTimeInterval(600)
        let sessionTwoEvents = [
            ActivityEvent(
                id: "pattern-2-0",
                occurredAt: sessionTwoStart,
                source: .workspace,
                kind: .appActivated,
                appName: "Codex",
                bundleID: "com.openai.codex",
                windowTitle: "onboarding flow"
            ),
            makeGitHubSupportEvent(at: sessionTwoStart.addingTimeInterval(60)),
            makeYouTubeDriftEvent(at: sessionTwoStart.addingTimeInterval(120)),
        ]
        let sessionTwoSegments = TimelineDeriver.deriveSegments(from: sessionTwoEvents, sessionEnd: sessionTwoStart.addingTimeInterval(180))
        try store.saveSession(
            StoredSession(
                id: "pattern-2",
                goal: "build the onboarding flow",
                startedAt: sessionTwoStart,
                endedAt: sessionTwoStart.addingTimeInterval(180),
                reviewStatus: .ready,
                primaryLabels: TimelineDeriver.primaryLabels(from: sessionTwoSegments)
            ),
            review: nil,
            segments: sessionTwoSegments,
            rawEventCount: sessionTwoEvents.count
        )

        let snapshot = store.contextPatternSnapshot(goal: "code the login form", excludingSessionID: "pattern-2")
        try require(snapshot != nil, "expected prior pattern snapshot")
        try require(snapshot?.sessionCount == 1, "expected excluding current session to leave one prior session")
        try require(snapshot?.alignedSurfaces.contains(where: { $0.localizedCaseInsensitiveContains("Codex") || $0.localizedCaseInsensitiveContains("driftly") || $0.localizedCaseInsensitiveContains("GitHub") }) == true, "expected aligned surfaces from prior build session")
        try require(snapshot?.driftSurfaces.contains(where: { $0.contains("YouTube") }) == true, "expected prior drift surface to include YouTube")
    }

    static func testPathNoiseFilterDropsTempChurn() throws {
        try require(
            PathNoiseFilter.shouldIgnoreFileActivity(
                path: "/var/folders/fx/abc123/T/TemporaryItems/NSIRD_screencaptureui_X4LJFl/.tmp.Ds5jV9CR"
            ),
            "expected screenshot temp files to be ignored"
        )
        try require(
            PathNoiseFilter.shouldIgnoreFileActivity(
                path: "/Users/aayush/ai-projects/driftly/.tmp.partial.tmp"
            ),
            "expected temporary .tmp files to be ignored"
        )
        try require(
            !PathNoiseFilter.shouldIgnoreFileActivity(
                path: "/Users/aayush/ai-projects/driftly/Sources/DriftlyApp/AppModel.swift"
            ),
            "expected normal project files to remain visible"
        )
    }

    static func testFocusGuardWaitsBeforePrompting() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(60)),
        ]

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: FocusGuardRuntimeState(),
            now: startedAt.addingTimeInterval(4 * 60),
            isUserIdle: false
        )

        try require(!decision.shouldPrompt, "expected no prompt before five minutes")
    }

    static func testFocusGuardSkipsIdleAndNearEnd() throws {
        let startedAt = Date(timeIntervalSince1970: 2_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 10)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]

        let idleDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: FocusGuardRuntimeState(),
            now: startedAt.addingTimeInterval(7 * 60),
            isUserIdle: true
        )
        try require(!idleDecision.shouldPrompt, "expected no prompt while idle")

        let nearEndDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: FocusGuardRuntimeState(),
            now: session.endsAt.addingTimeInterval(-90),
            isUserIdle: false
        )
        try require(!nearEndDecision.shouldPrompt, "expected no prompt in the final two minutes")
    }

    static func testFocusGuardRequiresContinuousDrift() throws {
        let startedAt = Date(timeIntervalSince1970: 3_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let firstState = FocusGuardRuntimeState(offTrackStartedAt: startedAt.addingTimeInterval(5 * 60))
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]

        let earlyDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: firstState,
            now: startedAt.addingTimeInterval(6 * 60),
            isUserIdle: false
        )
        try require(!earlyDecision.shouldPrompt, "expected no prompt before ninety seconds of drift")

        let readyDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: firstState,
            now: startedAt.addingTimeInterval(6 * 60 + 40),
            isUserIdle: false
        )
        try require(readyDecision.shouldPrompt, "expected prompt once drift is continuous for ninety seconds")
    }

    static func testFocusGuardKeepsAmbiguousSessionsQuiet() throws {
        let startedAt = Date(timeIntervalSince1970: 4_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeGitHubSupportEvent(at: startedAt.addingTimeInterval(5 * 60)),
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(6 * 60 + 30)),
        ]

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: FocusGuardRuntimeState(),
            now: startedAt.addingTimeInterval(8 * 60),
            isUserIdle: false
        )

        try require(decision.assessment.status == .unclear, "expected mixed evidence to stay unclear")
        try require(!decision.shouldPrompt, "expected no prompt for ambiguous sessions")
    }

    static func testFocusGuardCatchesDominantDrift() throws {
        let startedAt = Date(timeIntervalSince1970: 4_500)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeGitHubSupportEvent(at: startedAt.addingTimeInterval(5 * 60)),
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60 + 30)),
        ]

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: FocusGuardRuntimeState(),
            now: startedAt.addingTimeInterval(7 * 60 + 40),
            isUserIdle: false
        )

        try require(decision.assessment.status == .offTrack, "expected dominant recent YouTube drift to count as off-track")
        try require(decision.shouldPrompt, "expected a prompt once drift clearly dominates nearby work")
    }

    static func testFocusGuardRespectsCooldown() throws {
        let startedAt = Date(timeIntervalSince1970: 5_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]
        let state = FocusGuardRuntimeState(
            offTrackStartedAt: startedAt.addingTimeInterval(5 * 60),
            lastPromptAt: startedAt.addingTimeInterval(6 * 60),
            promptCount: 1,
            pendingRecoveryFromPromptAt: startedAt.addingTimeInterval(6 * 60)
        )

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: state,
            now: startedAt.addingTimeInterval(11 * 60),
            isUserIdle: false
        )

        try require(!decision.shouldPrompt, "expected cooldown to suppress a second prompt")
    }

    static func testFocusGuardCapsSessionPrompts() throws {
        let startedAt = Date(timeIntervalSince1970: 6_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]
        let state = FocusGuardRuntimeState(
            offTrackStartedAt: startedAt.addingTimeInterval(5 * 60),
            promptCount: 2
        )

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: state,
            now: startedAt.addingTimeInterval(8 * 60),
            isUserIdle: false
        )

        try require(!decision.shouldPrompt, "expected prompt cap to suppress additional nudges")
    }

    static func testFocusGuardPresetScalesPromptCaps() throws {
        let startedAt = Date(timeIntervalSince1970: 6_500)
        let settings = FocusGuardPreset.balanced.settings
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(2 * 60)),
        ]

        let mediumSessionDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30),
            events: events,
            settings: settings,
            state: FocusGuardRuntimeState(offTrackStartedAt: startedAt.addingTimeInterval(2 * 60), promptCount: 2),
            now: startedAt.addingTimeInterval(4 * 60),
            isUserIdle: false
        )
        try require(!mediumSessionDecision.shouldPrompt, "expected 30 minute session to cap at two prompts in balanced mode")

        let longSessionDecision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: makeFocusGuardSession(startedAt: startedAt, durationMinutes: 45),
            events: events,
            settings: settings,
            state: FocusGuardRuntimeState(offTrackStartedAt: startedAt.addingTimeInterval(2 * 60), promptCount: 2),
            now: startedAt.addingTimeInterval(4 * 60),
            isUserIdle: false
        )
        try require(longSessionDecision.shouldPrompt, "expected longer balanced session to allow a third prompt")
    }

    static func testFocusGuardSnoozeSuppressesPrompt() throws {
        let startedAt = Date(timeIntervalSince1970: 7_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]
        let state = FocusGuardRuntimeState(
            offTrackStartedAt: startedAt.addingTimeInterval(5 * 60),
            snoozedUntil: startedAt.addingTimeInterval(12 * 60)
        )

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: state,
            now: startedAt.addingTimeInterval(8 * 60),
            isUserIdle: false
        )

        try require(!decision.shouldPrompt, "expected snooze to suppress prompts")
    }

    static func testFocusGuardRecordsRecovery() throws {
        let startedAt = Date(timeIntervalSince1970: 8_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeGitHubSupportEvent(at: startedAt.addingTimeInterval(10 * 60)),
        ]
        let state = FocusGuardRuntimeState(
            pendingRecoveryFromPromptAt: startedAt.addingTimeInterval(9 * 60)
        )

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            state: state,
            now: startedAt.addingTimeInterval(10 * 60 + 30),
            isUserIdle: false
        )

        try require(decision.recordedRecovery, "expected recovery to be recorded after returning on track")
        try require(decision.state.lastRecoveryAt != nil, "expected recovery timestamp to be stored")
    }

    static func testFocusGuardReviewSummaryIncludesFacts() throws {
        let now = Date(timeIntervalSince1970: 9_000)
        let sessionID = "fg-summary"
        let events = [
            ActivityEvent(
                occurredAt: now,
                source: .manual,
                kind: .focusGuardPrompted,
                appName: "Driftly",
                resourceTitle: "Recent activity looks more like YouTube than work on this goal.",
                noteText: "You drifted to YouTube. Back to ship the settings migration?",
                relatedID: sessionID
            ),
            ActivityEvent(
                occurredAt: now.addingTimeInterval(60),
                source: .manual,
                kind: .focusGuardRecovered,
                appName: "Driftly",
                relatedID: sessionID
            ),
        ]

        let summary = FocusGuardEvaluator.reviewSummary(from: events, sessionID: sessionID)

        try require(summary.promptsShown == 1, "expected one prompt in summary")
        try require(summary.recoveries == 1, "expected one recovery in summary")
        try require(summary.recapSentence?.contains("back on track") == true, "expected recap sentence to mention recovery")
    }

    static func testFocusGuardDisabledNeverPrompts() throws {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        let session = makeFocusGuardSession(startedAt: startedAt, durationMinutes: 30)
        let events = [
            makeYouTubeDriftEvent(at: startedAt.addingTimeInterval(5 * 60)),
        ]

        let decision = FocusGuardEvaluator.evaluate(
            goal: "ship the settings migration",
            session: session,
            events: events,
            settings: FocusGuardSettings(enabled: false),
            state: FocusGuardRuntimeState(offTrackStartedAt: startedAt.addingTimeInterval(5 * 60)),
            now: startedAt.addingTimeInterval(8 * 60),
            isUserIdle: false
        )

        try require(!decision.shouldPrompt, "expected disabled focus guard to avoid prompts")
    }

    static func makeFocusGuardSession(startedAt: Date, durationMinutes: Int) -> FocusSession {
        FocusSession(
            id: UUID().uuidString,
            title: "ship the settings migration",
            durationMinutes: durationMinutes,
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
        )
    }

    static func makeYouTubeDriftEvent(at occurredAt: Date) -> ActivityEvent {
        ActivityEvent(
            occurredAt: occurredAt,
            source: .browser,
            kind: .tabFocused,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            resourceTitle: "YouTube Shorts",
            resourceURL: "https://www.youtube.com/shorts/abc123",
            domain: "youtube.com"
        )
    }

    static func makeGitHubSupportEvent(at occurredAt: Date) -> ActivityEvent {
        ActivityEvent(
            occurredAt: occurredAt,
            source: .browser,
            kind: .tabFocused,
            appName: "Google Chrome",
            bundleID: "com.google.Chrome",
            resourceTitle: "AayushMathur7/driftly pull request",
            resourceURL: "https://github.com/AayushMathur7/driftly/pull/42",
            domain: "github.com"
        )
    }

    static func makeTemporaryStore() -> SessionStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("driftly-selftest-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        return SessionStore(path: path)
    }

    static func seedSession(store: SessionStore, sessionID: String, goal: String) throws {
        let now = Date()
        try store.saveSession(
            StoredSession(
                id: sessionID,
                goal: goal,
                startedAt: now,
                endedAt: now.addingTimeInterval(300),
                reviewStatus: .ready,
                primaryLabels: []
            ),
            review: nil,
            segments: [],
            rawEventCount: 0
        )
    }

    static func seedFeedback(
        store: SessionStore,
        sessionID: String,
        helpful: Bool,
        note: String,
        goal: String,
        headline: String,
        summary: String
    ) throws {
        try seedSession(store: store, sessionID: sessionID, goal: goal)
        try store.saveReviewFeedback(
            SessionReviewFeedback(
                sessionID: sessionID,
                wasHelpful: helpful,
                note: note,
                goalSnapshot: goal,
                reviewHeadlineSnapshot: headline,
                reviewSummarySnapshot: summary,
                reviewTakeawaySnapshot: helpful ? "This framing worked." : "This framing missed the point."
            )
        )
    }
}

DriftlySelfTest.run()

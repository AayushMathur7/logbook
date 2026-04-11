import Foundation
import LogbookCore

struct SelfTestFailure: Error, CustomStringConvertible {
    let description: String
}

enum LogbookSelfTest {
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
            resourceTitle: "openai/logbook pull request",
            resourceURL: "https://github.com/openai/logbook/pull/42",
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
                windowTitle: "Logbook"
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
                windowTitle: "Logbook"
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
                workingDirectory: "/Users/aayush/ai-projects/logbook"
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
                resourceTitle: "openai/logbook pull request",
                resourceURL: "https://github.com/openai/logbook/pull/42",
                domain: "github.com"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one GitHub segment")
        try require(segments[0].primaryLabel == "GitHub", "expected GitHub primary label")
        try require(segments[0].secondaryLabel == "openai/logbook PR #42", "expected PR label")
        try require(segments[0].repoName == "logbook", "expected repo name")
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
                primaryLabel: "logbook",
                secondaryLabel: "Sources/LogbookApp/ContentView.swift",
                category: .coding,
                repoName: "logbook",
                filePath: "/Users/aayush/ai-projects/logbook/Sources/LogbookApp/ContentView.swift",
                confidence: 0.9,
                eventCount: 3
            ),
        ]

        let observed = TimelineDeriver.observeSegments(segments, goal: "Work on Logbook timeline UI")
        let summary = TimelineDeriver.summarizeObservedSegments(observed)

        try require(observed.count == 1, "expected one observed segment")
        try require(observed[0].role == .direct, "expected direct role for goal-aligned file editing")
        try require(observed[0].goalRelevance >= 0.45, "expected strong relevance for logbook file editing")
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
                secondaryLabel: "openai/logbook PR #42",
                category: .coding,
                repoName: "logbook",
                url: "https://github.com/openai/logbook/pull/42",
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

        let observed = TimelineDeriver.observeSegments(segments, goal: "Work on Logbook timeline UI")
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
                secondaryLabel: "openai/logbook PR #42",
                category: .coding,
                repoName: "logbook",
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
                resourceTitle: "openai/logbook pull request",
                resourceURL: "https://github.com/openai/logbook/pull/42",
                domain: "github.com"
            ),
            ActivityEvent(
                occurredAt: now.addingTimeInterval(60),
                source: .browser,
                kind: .tabChanged,
                appName: "Google Chrome",
                bundleID: "com.google.Chrome",
                resourceTitle: "openai/logbook pull request",
                resourceURL: "https://github.com/openai/logbook/pull/42",
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
                windowTitle: "ActivityMonitor.swift — logbook — Untracked"
            ),
        ]

        let segments = TimelineDeriver.deriveSegments(from: events, sessionEnd: now.addingTimeInterval(60))
        try require(segments.count == 1, "expected one editor segment")
        try require(segments[0].primaryLabel == "logbook", "expected repo label from editor title")
        try require(segments[0].secondaryLabel == "ActivityMonitor.swift", "expected file label from editor title")
        try require(segments[0].repoName == "logbook", "expected repo name to be inferred")
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
}

LogbookSelfTest.run()

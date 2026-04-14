import Foundation

public enum TimelineDeriver {
    public static func deriveSegments(from events: [ActivityEvent], sessionEnd: Date? = nil) -> [TimelineSegment] {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard !sorted.isEmpty else { return [] }

        let upperBound = sessionEnd ?? sorted.last?.occurredAt ?? Date()
        var segments: [SegmentAccumulator] = []

        for (index, event) in sorted.enumerated() {
            let nextAt = index + 1 < sorted.count ? sorted[index + 1].occurredAt : upperBound
            let descriptor = descriptor(for: event)
            let eventEnd = max(event.occurredAt, min(nextAt, upperBound))

            if shouldStartStandaloneSegment(for: event, descriptor: descriptor) {
                segments.append(
                    SegmentAccumulator(
                        descriptor: descriptor,
                        startAt: event.occurredAt,
                        endAt: eventEnd,
                        eventCount: 1
                    )
                )
                continue
            }

            if let last = segments.last,
               last.canMerge(with: descriptor, nextStartAt: event.occurredAt) {
                segments[segments.count - 1].merge(eventAt: event.occurredAt, endAt: eventEnd)
            } else {
                segments.append(
                    SegmentAccumulator(
                        descriptor: descriptor,
                        startAt: event.occurredAt,
                        endAt: eventEnd,
                        eventCount: 1
                    )
                )
            }
        }

        return segments.map(\.timelineSegment)
    }

    public static func primaryLabels(from segments: [TimelineSegment], limit: Int = 2) -> [String] {
        Array(
            segments
                .map(\.primaryLabel)
                .reduce(into: [String]()) { labels, label in
                    guard !labels.contains(label) else { return }
                    labels.append(label)
                }
                .prefix(limit)
        )
    }

    public static func repoName(from events: [ActivityEvent]) -> String? {
        for event in events.reversed() {
            let descriptor = descriptor(for: event)
            if let repoName = descriptor.entity.repoName {
                return repoName
            }
        }
        return nil
    }

    public static func deriveIntent(from goal: String) -> SessionIntent {
        let normalized = goal.lowercased()
        let goalTerms = goalKeywords(from: goal)
        let matchedTargets = knownIntentTargets.compactMap { canonical, aliases -> String? in
            aliases.contains(where: { normalized.contains($0) }) ? canonical : nil
        }

        let modeCandidates: [(SessionIntentMode, [String])] = [
            (.watch, ["watch", "youtube", "video", "videos", "shorts", "movie", "stream"]),
            (.listen, ["listen", "spotify", "song", "songs", "music", "album", "playlist", "podcast"]),
            (.browse, ["browse", "scroll", "surf", "explore", "check x", "check twitter", "check linkedin"]),
            (.review, ["review", "pr", "pull request", "issue", "compare", "diff", "feedback"]),
            (.write, ["write", "draft", "copy", "blog", "doc", "docs", "memo", "spec", "proposal"]),
            (.research, ["research", "learn", "read", "study", "investigate", "look into"]),
            (.communicate, ["message", "messages", "reply", "email", "mail", "slack", "dm"]),
            (.admin, ["calendar", "schedule", "plan", "planning", "organize", "admin"]),
            (.build, ["build", "ship", "deploy", "debug", "fix", "implement", "code", "repo", "github", "cursor", "codex", "xcode"]),
        ]

        let scoredModes = modeCandidates
            .map { mode, hints in
                let score = hints.reduce(0) { partial, hint in
                    partial + (normalized.contains(hint) ? 1 : 0)
                }
                return (mode: mode, score: score)
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.mode.rawValue < $1.mode.rawValue
                }
                return $0.score > $1.score
            }

        let mode: SessionIntentMode
        if scoredModes.count >= 2, scoredModes[0].score == scoredModes[1].score {
            mode = .mixed
        } else {
            mode = scoredModes.first?.mode ?? .unknown
        }

        let action = primaryIntentAction(in: normalized, mode: mode)
        let objectTerms = Array(
            goalTerms
                .filter { term in
                    !matchedTargets.contains(where: { $0.replacingOccurrences(of: " ", with: "") == term })
                }
                .sorted()
                .prefix(5)
        )

        let confidence = min(
            0.98,
            0.25
                + (matchedTargets.isEmpty ? 0 : 0.25)
                + (mode == .unknown ? 0 : 0.2)
                + (objectTerms.isEmpty ? 0 : 0.12)
                + (action == nil ? 0 : 0.08)
        )

        return SessionIntent(
            rawGoal: goal,
            mode: mode,
            action: action,
            targets: matchedTargets,
            objects: objectTerms,
            confidence: confidence
        )
    }

    public static func observeSegments(_ segments: [TimelineSegment], goal: String) -> [ObservedTimelineSegment] {
        let intent = deriveIntent(from: goal)
        let goalTerms = goalKeywords(from: goal)

        return segments.map { segment in
            let relevance = goalRelevance(for: segment, goal: goal, goalTerms: goalTerms)
            let role = segmentRole(for: segment, relevance: relevance, intent: intent)
            let rationale = segmentRationale(for: segment, role: role, relevance: relevance, intent: intent)
            return ObservedTimelineSegment(
                segment: segment,
                role: role,
                goalRelevance: relevance,
                rationale: rationale
            )
        }
    }

    public static func summarizeObservedSegments(_ observedSegments: [ObservedTimelineSegment]) -> SessionObservabilitySummary {
        guard !observedSegments.isEmpty else { return SessionObservabilitySummary() }

        var directSeconds = 0
        var supportSeconds = 0
        var driftSeconds = 0
        var breakSeconds = 0
        var neutralSeconds = 0
        var longestDirectRunSeconds = 0
        var currentDirectRunSeconds = 0
        var driftInterruptions = 0
        var previousNonDriftRole: SessionSegmentRole?

        for observed in observedSegments {
            let seconds = max(Int(observed.segment.endAt.timeIntervalSince(observed.segment.startAt).rounded()), 0)

            switch observed.role {
            case .direct:
                directSeconds += seconds
                currentDirectRunSeconds += seconds
            case .support:
                supportSeconds += seconds
                currentDirectRunSeconds = 0
            case .drift:
                driftSeconds += seconds
                currentDirectRunSeconds = 0
                if let previousNonDriftRole, previousNonDriftRole == .direct || previousNonDriftRole == .support {
                    driftInterruptions += 1
                }
            case .breakTime:
                breakSeconds += seconds
                currentDirectRunSeconds = 0
                if let previousNonDriftRole, previousNonDriftRole == .direct || previousNonDriftRole == .support {
                    driftInterruptions += 1
                }
            case .neutral:
                neutralSeconds += seconds
                currentDirectRunSeconds = 0
            }

            longestDirectRunSeconds = max(longestDirectRunSeconds, currentDirectRunSeconds)

            if observed.role == .direct || observed.role == .support {
                previousNonDriftRole = observed.role
            }
        }

        let totalSeconds = max(directSeconds + supportSeconds + driftSeconds + breakSeconds + neutralSeconds, 1)
        let directRatio = Double(directSeconds) / Double(totalSeconds)
        let productiveRatio = Double(directSeconds + supportSeconds) / Double(totalSeconds)

        let goalProgressEstimate: SessionGoalProgressEstimate
        if directRatio >= 0.5 && longestDirectRunSeconds >= 180 {
            goalProgressEstimate = .strong
        } else if directRatio >= 0.2 || productiveRatio >= 0.55 {
            goalProgressEstimate = .partial
        } else if productiveRatio >= 0.2 {
            goalProgressEstimate = .weak
        } else {
            goalProgressEstimate = .none
        }

        return SessionObservabilitySummary(
            directSeconds: directSeconds,
            supportSeconds: supportSeconds,
            driftSeconds: driftSeconds,
            breakSeconds: breakSeconds,
            neutralSeconds: neutralSeconds,
            longestDirectRunSeconds: longestDirectRunSeconds,
            driftInterruptions: driftInterruptions,
            goalProgressEstimate: goalProgressEstimate
        )
    }

    private static func shouldStartStandaloneSegment(for event: ActivityEvent, descriptor: EventDescriptor) -> Bool {
        event.kind == .userIdle
            || event.kind == .userResumed
            || event.kind == .systemSlept
            || event.kind == .systemWoke
            || descriptor.entity.kind == .note
    }

    public static func descriptor(for event: ActivityEvent) -> EventDescriptor {
        if event.kind == .userIdle {
            return EventDescriptor(
                appName: "System",
                category: .admin,
                entity: DerivedEntity(kind: .presence, primaryLabel: "Idle", confidence: 1.0)
            )
        }
        if event.kind == .userResumed {
            return EventDescriptor(
                appName: "System",
                category: .admin,
                entity: DerivedEntity(kind: .presence, primaryLabel: "Resumed", confidence: 1.0)
            )
        }
        if event.kind == .systemSlept || event.kind == .systemWoke {
            return EventDescriptor(
                appName: "System",
                category: .admin,
                entity: DerivedEntity(
                    kind: .system,
                    primaryLabel: event.kind == .systemSlept ? "System slept" : "System woke",
                    confidence: 1.0
                )
            )
        }
        if let note = event.noteText?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            return EventDescriptor(
                appName: event.appName ?? "Driftly",
                category: .admin,
                entity: DerivedEntity(kind: .note, primaryLabel: note, confidence: 1.0)
            )
        }

        let appName = event.appName ?? inferredAppName(from: event)

        if let pathEntity = pathEntity(for: event, appName: appName) {
            return EventDescriptor(appName: appName, category: .coding, entity: pathEntity)
        }

        if let webEntity = webEntity(for: event, appName: appName) {
            return EventDescriptor(appName: appName, category: category(for: webEntity, appName: appName), entity: webEntity)
        }

        if let title = (event.resourceTitle ?? event.windowTitle)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return EventDescriptor(
                appName: appName,
                category: category(forAppName: appName),
                entity: DerivedEntity(kind: .app, primaryLabel: cleanedTitle(title) ?? title, confidence: 0.45)
            )
        }

        return EventDescriptor(
            appName: appName,
            category: category(forAppName: appName),
            entity: DerivedEntity(kind: .app, primaryLabel: appName, confidence: 0.3)
        )
    }

    private static func inferredAppName(from event: ActivityEvent) -> String {
        switch event.source {
        case .shell:
            return "Terminal"
        case .browser:
            return "Browser"
        case .fileSystem:
            return "File activity"
        case .system:
            return "System"
        case .manual:
            return "Driftly"
        default:
            return "Activity"
        }
    }

    private static func pathEntity(for event: ActivityEvent, appName: String) -> DerivedEntity? {
        if let command = event.command, let workingDirectory = event.workingDirectory {
            let repo = derivedRepoName(fromPath: workingDirectory)
            return DerivedEntity(
                kind: .repo,
                primaryLabel: repo ?? URL(fileURLWithPath: workingDirectory).lastPathComponent,
                secondaryLabel: command,
                repoName: repo,
                filePath: nil,
                url: nil,
                domain: nil,
                confidence: 0.9
            )
        }

        if let filePath = plausibleFilePath(from: event, appName: appName) {
            let repo = derivedRepoName(fromPath: filePath)
            return DerivedEntity(
                kind: .file,
                primaryLabel: repo ?? URL(fileURLWithPath: filePath).deletingLastPathComponent().lastPathComponent,
                secondaryLabel: relativeDisplayPath(filePath, repoName: repo),
                repoName: repo,
                filePath: filePath,
                confidence: 0.88
            )
        }

        if let titleEntity = editorTitleEntity(for: event, appName: appName) {
            return titleEntity
        }

        if let workingDirectory = event.workingDirectory, !workingDirectory.isEmpty {
            let repo = derivedRepoName(fromPath: workingDirectory)
            return DerivedEntity(
                kind: .repo,
                primaryLabel: repo ?? URL(fileURLWithPath: workingDirectory).lastPathComponent,
                secondaryLabel: nil,
                repoName: repo,
                filePath: nil,
                confidence: 0.75
            )
        }

        return nil
    }

    private static func editorTitleEntity(for event: ActivityEvent, appName: String) -> DerivedEntity? {
        let lowerApp = appName.lowercased()
        guard lowerApp.contains("cursor") || lowerApp.contains("code") || lowerApp.contains("xcode") || lowerApp.contains("codex") else {
            return nil
        }

        guard let title = cleanedTitle(event.windowTitle ?? event.resourceTitle) else {
            return nil
        }

        let separators = [" — ", " – ", " - "]
        let components = separators.compactMap { separator -> [String]? in
            let parts = title.components(separatedBy: separator).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return parts.count >= 2 ? parts : nil
        }.first ?? [title]

        guard let first = components.first, !first.isEmpty else {
            return nil
        }

        let repoCandidate = components.dropFirst().first(where: { part in
            let lowered = part.lowercased()
            return !part.isEmpty && !lowered.contains("edited") && !lowered.contains("untracked")
        })
        let fileCandidate = first.contains(".") ? first : nil

        guard fileCandidate != nil || repoCandidate != nil else {
            return nil
        }

        let primary = repoCandidate ?? fileCandidate ?? title
        let secondary = fileCandidate
        let filePath = fileCandidate ?? title

        return DerivedEntity(
            kind: .file,
            primaryLabel: primary,
            secondaryLabel: secondary,
            repoName: repoCandidate,
            filePath: filePath,
            confidence: 0.78
        )
    }

    private static func plausibleFilePath(from event: ActivityEvent, appName: String) -> String? {
        if let path = event.path, isFilePath(path) {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }

        let lowerApp = appName.lowercased()
        guard lowerApp.contains("cursor") || lowerApp.contains("code") || lowerApp.contains("xcode") else {
            return nil
        }

        if let title = event.windowTitle ?? event.resourceTitle {
            return extractLikelyFilePath(fromWindowTitle: title)
        }

        return nil
    }

    private static func webEntity(for event: ActivityEvent, appName: String) -> DerivedEntity? {
        guard let rawURL = event.resourceURL, let url = URL(string: rawURL), let host = normalizedHost(url.host) else {
            return nil
        }

        if host == "github.com" {
            return githubEntity(url: url, fallbackTitle: event.resourceTitle)
        }
        if host == "youtube.com" || host == "youtu.be" {
            return youtubeEntity(url: url, fallbackTitle: event.resourceTitle)
        }
        if host == "x.com" || host == "twitter.com" {
            return xEntity(url: url, fallbackTitle: event.resourceTitle)
        }
        if host.contains("calendar.notion.so") {
            return notionCalendarEntity(url: url, fallbackTitle: event.resourceTitle)
        }

        let title = cleanedTitle(event.resourceTitle ?? event.windowTitle) ?? host
        return DerivedEntity(
            kind: .web,
            primaryLabel: host,
            secondaryLabel: title == host ? nil : title,
            url: rawURL,
            domain: host,
            confidence: 0.72
        )
    }

    private static func notionCalendarEntity(url: URL, fallbackTitle: String?) -> DerivedEntity {
        let title = cleanedTitle(fallbackTitle)
        let secondary: String?

        if let title, !title.lowercased().contains("calendar.notion.so") {
            secondary = title
        } else {
            let path = url.pathComponents.filter { $0 != "/" }.joined(separator: "/")
            secondary = path.isEmpty ? nil : path
        }

        return DerivedEntity(
            kind: .web,
            primaryLabel: "Notion Calendar",
            secondaryLabel: secondary,
            url: url.absoluteString,
            domain: "calendar.notion.so",
            confidence: 0.9
        )
    }

    private static func githubEntity(url: URL, fallbackTitle: String?) -> DerivedEntity {
        let parts = url.pathComponents.filter { $0 != "/" }
        let repo = parts.count >= 2 ? "\(parts[0])/\(parts[1])" : "GitHub"
        var secondary = repo

        if parts.count >= 4 && parts[2] == "pull" {
            secondary = "\(repo) PR #\(parts[3])"
        } else if parts.count >= 4 && parts[2] == "issues" {
            secondary = "\(repo) Issue #\(parts[3])"
        } else if parts.count >= 4 && parts[2] == "commit" {
            secondary = "\(repo) Commit"
        } else if parts.count >= 4 && parts[2] == "compare" {
            secondary = "\(repo) Compare"
        } else if parts.count >= 3 && parts[2] == "actions" {
            secondary = "\(repo) Actions"
        } else if parts.count >= 5 && parts[2] == "blob" {
            secondary = "\(repo) \(parts.dropFirst(4).joined(separator: "/"))"
        } else if parts.count >= 3 && parts[2] == "wiki" {
            secondary = "\(repo) Wiki"
        }

        return DerivedEntity(
            kind: .web,
            primaryLabel: "GitHub",
            secondaryLabel: secondary == "GitHub" ? cleanedTitle(fallbackTitle) : secondary,
            repoName: parts.count >= 2 ? parts[1] : nil,
            filePath: parts.count >= 5 && parts[2] == "blob" ? parts.dropFirst(4).joined(separator: "/") : nil,
            url: url.absoluteString,
            domain: "github.com",
            confidence: 0.96
        )
    }

    private static func youtubeEntity(url: URL, fallbackTitle: String?) -> DerivedEntity {
        let host = normalizedHost(url.host) ?? "youtube.com"
        let parts = url.pathComponents.filter { $0 != "/" }
        var primary = "YouTube"
        var secondary = cleanedTitle(fallbackTitle)

        if host == "youtu.be", let first = parts.first {
            primary = "YouTube Watch"
            secondary = secondary ?? first
        } else if parts.first == "shorts", let id = parts.dropFirst().first {
            primary = "YouTube Shorts"
            secondary = secondary ?? id
        } else if parts.first == "watch" {
            primary = "YouTube Watch"
            secondary = secondary ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value
        } else if parts.first == "results" {
            primary = "YouTube Search"
        } else if parts.first == "channel" || parts.first == "@" {
            primary = "YouTube Channel"
        } else if parts.isEmpty {
            primary = "YouTube Home"
        }

        return DerivedEntity(
            kind: .web,
            primaryLabel: primary,
            secondaryLabel: secondary,
            url: url.absoluteString,
            domain: "youtube.com",
            confidence: 0.92
        )
    }

    private static func xEntity(url: URL, fallbackTitle: String?) -> DerivedEntity {
        let parts = url.pathComponents.filter { $0 != "/" }
        let primary = "X"
        var secondary = cleanedTitle(fallbackTitle)

        if parts.first == "home" {
            secondary = "Home feed"
        } else if parts.first == "search" {
            secondary = "Search"
        } else if parts.first == "notifications" {
            secondary = "Notifications"
        } else if parts.first == "messages" || parts.first == "i" {
            secondary = "Messages"
        } else if parts.count >= 3 && parts[1] == "status" {
            secondary = "@\(parts[0]) post"
        } else if let user = parts.first {
            secondary = "@\(user)"
        }

        return DerivedEntity(
            kind: .web,
            primaryLabel: primary,
            secondaryLabel: secondary,
            url: url.absoluteString,
            domain: normalizedHost(url.host),
            confidence: 0.94
        )
    }

    private static func category(for entity: DerivedEntity, appName: String) -> ActivityCategory {
        if entity.kind == .file || entity.kind == .repo {
            return .coding
        }

        if let domain = entity.domain {
            switch domain {
            case "github.com":
                return .coding
            case "youtube.com", "youtu.be":
                return .media
            case "x.com", "twitter.com":
                return .social
            default:
                break
            }
        }

        return category(forAppName: appName)
    }

    private static func category(forAppName appName: String) -> ActivityCategory {
        let lower = appName.lowercased()
        if lower.contains("cursor") || lower.contains("code") || lower.contains("xcode") || lower.contains("terminal") {
            return .coding
        }
        if lower.contains("docs") || lower.contains("preview") {
            return .docs
        }
        if lower.contains("mail") || lower.contains("message") || lower.contains("slack") || lower.contains("discord") {
            return .communication
        }
        if lower.contains("calendar") || lower.contains("finder") || lower.contains("system") {
            return .admin
        }
        if lower.contains("spotify") || lower.contains("music") {
            return .media
        }
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("brave") {
            return .research
        }
        return .unknown
    }

    private static func segmentRole(for segment: TimelineSegment, relevance: Double, intent: SessionIntent) -> SessionSegmentRole {
        let alignment = alignmentScore(for: segment, relevance: relevance, intent: intent)

        if isBreakSegment(segment) {
            return .breakTime
        }

        if alignment >= 0.65 {
            return .direct
        }
        if alignment >= 0.2 {
            return .support
        }
        if alignment <= -0.15 {
            return .drift
        }
        return .neutral
    }

    private static func alignmentScore(for segment: TimelineSegment, relevance: Double, intent: SessionIntent) -> Double {
        let lowerPrimary = segment.primaryLabel.lowercased()
        let lowerSecondary = segment.secondaryLabel?.lowercased() ?? ""
        let lowerApp = segment.appName.lowercased()
        let domain = (segment.domain ?? "").lowercased()
        let surfaceTokens = segmentIntentTokens(for: segment)
        let targetMatchCount = intent.targets.filter { surfaceTokens.contains($0) }.count
        let hasExplicitSurfaceTargets = !intent.targets.isEmpty
        let surfaceMismatch = hasExplicitSurfaceTargets && targetMatchCount == 0 && surfaceTokens.contains(where: knownIntentTargets.keys.contains)

        var score = (relevance * 0.8) - 0.1

        if targetMatchCount > 0 {
            score += 0.55 + min(Double(targetMatchCount - 1) * 0.08, 0.16)
        } else if surfaceMismatch {
            score -= 0.24
        }

        if lowerPrimary.contains("new tab") || lowerSecondary.contains("new tab") {
            score -= 0.3
        }

        if objectBlob(for: segment).contains(where: { object in
            intent.objects.contains(where: { object.contains($0) || $0.contains(object) })
        }) {
            score += 0.08
        }

        score += modeAffinity(for: segment, intent: intent)

        if segment.category == .media || segment.category == .social {
            switch intent.mode {
            case .watch, .listen, .browse, .research:
                break
            default:
                score -= targetMatchCount > 0 ? 0 : 0.14
            }
        }

        if domain.contains("calendar.notion.so") || lowerPrimary.contains("calendar") || lowerSecondary.contains("calendar") {
            score += intent.mode == .admin || intent.mode == .research ? 0.16 : -0.08
        }

        if segment.filePath != nil {
            score += intent.mode == .build || intent.mode == .write || intent.mode == .review ? 0.16 : 0.05
        }

        if lowerApp.contains("cursor") || lowerApp.contains("codex") || lowerApp.contains("xcode") || lowerApp.contains("code") {
            score += intent.mode == .build || intent.mode == .review ? 0.18 : 0.04
        }

        if domain == "github.com" {
            score += intent.mode == .build || intent.mode == .review || intent.mode == .research ? 0.16 : 0.02
        }

        return min(max(score, -1), 1)
    }

    private static func modeAffinity(for segment: TimelineSegment, intent: SessionIntent) -> Double {
        let lowerPrimary = segment.primaryLabel.lowercased()
        let lowerSecondary = segment.secondaryLabel?.lowercased() ?? ""
        let lowerApp = segment.appName.lowercased()
        let domain = (segment.domain ?? "").lowercased()

        switch intent.mode {
        case .watch:
            if domain == "youtube.com" || domain == "youtu.be" || lowerPrimary.contains("watch") || lowerPrimary.contains("shorts") {
                return 0.34
            }
            if segment.category == .media {
                return 0.12
            }
            if domain == "x.com" || domain == "twitter.com" || segment.category == .social {
                return -0.18
            }
        case .listen:
            if lowerApp.contains("spotify") || lowerApp.contains("music") || lowerPrimary.contains("spotify") || lowerSecondary.contains("spotify") {
                return 0.34
            }
            if domain == "youtube.com" || domain == "youtu.be" {
                return -0.08
            }
        case .browse:
            if domain == "x.com" || domain == "twitter.com" || segment.category == .social {
                return 0.24
            }
            if segment.url != nil || domain == "youtube.com" || domain == "youtu.be" {
                return 0.08
            }
        case .review:
            if domain == "github.com" || segment.category == .docs || segment.category == .research {
                return 0.22
            }
            if segment.filePath != nil {
                return 0.1
            }
        case .write:
            if segment.category == .docs || segment.filePath != nil {
                return 0.22
            }
            if domain == "docs.google.com" {
                return 0.28
            }
        case .research:
            if segment.category == .research || segment.category == .docs {
                return 0.18
            }
            if domain == "youtube.com" || domain == "youtu.be" || domain == "github.com" {
                return 0.12
            }
            if domain == "x.com" || domain == "twitter.com", lowerSecondary == "home feed" {
                return -0.12
            }
        case .communicate:
            if lowerApp.contains("mail") || lowerApp.contains("messages") || lowerApp.contains("slack") || domain.contains("gmail.com") {
                return 0.28
            }
        case .admin:
            if domain.contains("calendar") || lowerPrimary.contains("calendar") || lowerSecondary.contains("calendar") {
                return 0.28
            }
            if lowerPrimary.contains("settings") || lowerApp.contains("settings") {
                return 0.14
            }
        case .build:
            if domain == "github.com" {
                return 0.1
            }
            if segment.filePath != nil {
                return 0.24
            }
            if segment.repoName != nil {
                return 0.18
            }
            if segment.category == .coding {
                return 0.16
            }
            if segment.category == .media || segment.category == .social {
                return -0.22
            }
        case .mixed:
            if segment.category == .coding || segment.category == .docs || segment.category == .research {
                return 0.08
            }
        case .unknown:
            break
        }

        return 0
    }

    private static func goalRelevance(for segment: TimelineSegment, goal: String, goalTerms: Set<String>) -> Double {
        var score = 0.0
        let normalizedGoal = goal.lowercased()
        let blob = [
            segment.appName,
            segment.primaryLabel,
            segment.secondaryLabel ?? "",
            segment.repoName ?? "",
            segment.filePath ?? "",
            segment.url ?? "",
            segment.domain ?? "",
        ]
            .joined(separator: " ")
            .lowercased()

        if let repoName = segment.repoName?.lowercased(), !repoName.isEmpty, normalizedGoal.contains(repoName) {
            score += 0.38
        }

        if let filePath = segment.filePath?.lowercased(), !filePath.isEmpty {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent.lowercased()
            if normalizedGoal.contains(fileName) {
                score += 0.4
            }
            if let repoName = segment.repoName?.lowercased(), filePath.contains("/\(repoName)/"), normalizedGoal.contains(repoName) {
                score += 0.18
            }
        }

        let matchedTerms = goalTerms.filter { blob.contains($0) }
        score += min(Double(matchedTerms.count) * 0.14, 0.42)

        if segment.category == .coding || segment.category == .docs {
            score += 0.12
        }
        if (segment.domain ?? "").lowercased() == "github.com" {
            score += 0.1
        }
        if segment.filePath != nil {
            score += 0.12
        }

        return min(max(score, 0), 1)
    }

    private static func segmentRationale(for segment: TimelineSegment, role: SessionSegmentRole, relevance: Double, intent: SessionIntent) -> String {
        let domain = (segment.domain ?? "").lowercased()
        if role == .drift {
            if !intent.targets.isEmpty {
                return "This pulled the session away from the stated intent rather than supporting it."
            }
            if isBreakSegment(segment) {
                return "Manual note marked a break inside the session."
            }
            return "Observed activity did not look aligned with the stated intent."
        }

        if role == .direct {
            if !intent.targets.isEmpty {
                return "This matched the stated intent closely enough to count as the main thread of the session."
            }
            if let filePath = segment.filePath {
                return "Active file context matched the likely work object: \(URL(fileURLWithPath: filePath).lastPathComponent)."
            }
            if let repoName = segment.repoName {
                return "Repo context aligned with the session goal: \(repoName)."
            }
            return "Segment looked like direct execution work with strong goal relevance."
        }

        if role == .support {
            if !intent.targets.isEmpty {
                return relevance >= 0.35
                    ? "This stayed near the stated intent, but was less central than the main thread."
                    : "This looked adjacent to the stated intent without being the core activity."
            }
            if domain == "github.com" {
                return "GitHub context looked relevant, but browser review is treated as support work."
            }
            if domain.contains("calendar.notion.so") {
                return "Calendar context looked adjacent to the goal, but not direct execution."
            }
            return relevance >= 0.35
                ? "This looked adjacent to the goal, but not like direct implementation."
                : "This looked like contextual or administrative support work."
        }

        if role == .breakTime {
            return "This segment was treated as a break."
        }

        return "This segment was observed, but its connection to the goal was weak."
    }
}

public struct EventDescriptor: Hashable {
    public let appName: String
    public let category: ActivityCategory
    public let entity: DerivedEntity

    public init(appName: String, category: ActivityCategory, entity: DerivedEntity) {
        self.appName = appName
        self.category = category
        self.entity = entity
    }
}

private struct SegmentAccumulator {
    let descriptor: EventDescriptor
    var startAt: Date
    var endAt: Date
    var eventCount: Int

    func canMerge(with descriptor: EventDescriptor, nextStartAt: Date) -> Bool {
        let gap = nextStartAt.timeIntervalSince(endAt)
        guard gap <= 120 else { return false }
        return self.descriptor.appName == descriptor.appName
            && self.descriptor.category == descriptor.category
            && self.descriptor.entity.primaryLabel == descriptor.entity.primaryLabel
            && self.descriptor.entity.secondaryLabel == descriptor.entity.secondaryLabel
            && self.descriptor.entity.repoName == descriptor.entity.repoName
            && self.descriptor.entity.filePath == descriptor.entity.filePath
            && self.descriptor.entity.domain == descriptor.entity.domain
    }

    mutating func merge(eventAt: Date, endAt: Date) {
        self.endAt = max(self.endAt, endAt)
        if eventAt >= startAt {
            eventCount += 1
        }
    }

    var timelineSegment: TimelineSegment {
        TimelineSegment(
            startAt: startAt,
            endAt: endAt,
            appName: descriptor.appName,
            primaryLabel: descriptor.entity.primaryLabel,
            secondaryLabel: descriptor.entity.secondaryLabel,
            category: descriptor.category,
            repoName: descriptor.entity.repoName,
            filePath: descriptor.entity.filePath,
            url: descriptor.entity.url,
            domain: descriptor.entity.domain,
            confidence: descriptor.entity.confidence,
            eventCount: eventCount
        )
    }
}

private func cleanedTitle(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let patterns = [
        #"\s+[—–-]\s+(Google Chrome|Arc|Safari)(\s+[—–-]\s+.+)?$"#,
        #"\s+\|\s+(Google Chrome|Arc|Safari)$"#
    ]

    var cleaned = trimmed
    for pattern in patterns {
        cleaned = cleaned.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }

    let final = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    return final.isEmpty ? nil : final
}

private let knownIntentTargets: [String: [String]] = [
    "youtube": ["youtube", "youtu.be", "video", "videos", "shorts"],
    "x": ["x", "x.com", "twitter", "twitter.com"],
    "spotify": ["spotify", "music", "song", "songs", "playlist", "album"],
    "github": ["github", "repo", "repository", "pull request", "pr", "issue"],
    "notion-calendar": ["notion calendar", "calendar.notion.so", "calendar"],
    "notion": ["notion"],
    "cursor": ["cursor"],
    "codex": ["codex"],
    "chrome": ["chrome", "google chrome"],
    "safari": ["safari"],
    "terminal": ["terminal", "shell", "command line"],
    "google-docs": ["google docs", "docs.google.com"],
    "google-drive": ["google drive", "drive.google.com"],
]

private func primaryIntentAction(in normalizedGoal: String, mode: SessionIntentMode) -> String? {
    let actionsByMode: [SessionIntentMode: [String]] = [
        .watch: ["watch"],
        .listen: ["listen"],
        .browse: ["browse", "scroll", "explore"],
        .review: ["review"],
        .write: ["write", "draft"],
        .research: ["research", "read", "learn"],
        .communicate: ["message", "reply", "email"],
        .admin: ["plan", "schedule", "organize"],
        .build: ["build", "ship", "deploy", "debug", "fix", "implement", "code"],
    ]

    for action in actionsByMode[mode] ?? [] where normalizedGoal.contains(action) {
        return action
    }

    return nil
}

private func goalKeywords(from goal: String) -> Set<String> {
    let stopWords: Set<String> = [
        "a", "an", "and", "for", "from", "into", "my", "of", "on", "or",
        "the", "to", "with", "work", "working", "focus", "focused", "session",
        "block", "ship", "make", "build", "fix", "review", "wanna", "want",
        "just", "please", "need", "i", "me"
    ]

    let normalized = goal
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)

    return Set(
        normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    )
}

private func segmentIntentTokens(for segment: TimelineSegment) -> Set<String> {
    var tokens: Set<String> = []
    let lowerPrimary = segment.primaryLabel.lowercased()
    let lowerSecondary = segment.secondaryLabel?.lowercased() ?? ""
    let lowerApp = segment.appName.lowercased()
    let domain = (segment.domain ?? "").lowercased()

    if domain == "youtube.com" || domain == "youtu.be" || lowerPrimary.contains("youtube") {
        tokens.insert("youtube")
    }
    if domain == "x.com" || domain == "twitter.com" || lowerPrimary == "x" || lowerSecondary.contains("@") {
        tokens.insert("x")
    }
    if lowerApp.contains("spotify") || lowerPrimary.contains("spotify") || lowerSecondary.contains("spotify") {
        tokens.insert("spotify")
    }
    if domain == "github.com" || lowerPrimary.contains("github") || lowerSecondary.contains("/") {
        tokens.insert("github")
    }
    if domain.contains("calendar.notion.so") || lowerPrimary.contains("calendar") || lowerSecondary.contains("calendar") {
        tokens.insert("notion-calendar")
        tokens.insert("notion")
    } else if lowerPrimary.contains("notion") || lowerSecondary.contains("notion") {
        tokens.insert("notion")
    }
    if lowerApp.contains("cursor") || lowerPrimary.contains("cursor") {
        tokens.insert("cursor")
    }
    if lowerApp.contains("codex") || lowerPrimary.contains("codex") {
        tokens.insert("codex")
    }
    if lowerApp.contains("chrome") {
        tokens.insert("chrome")
    }
    if lowerApp.contains("safari") {
        tokens.insert("safari")
    }
    if lowerApp.contains("terminal") || lowerApp.contains("ghostty") || lowerApp.contains("iterm") {
        tokens.insert("terminal")
    }
    if domain == "docs.google.com" {
        tokens.insert("google-docs")
    }
    if domain == "drive.google.com" {
        tokens.insert("google-drive")
    }

    return tokens
}

private func objectBlob(for segment: TimelineSegment) -> [String] {
    [
        segment.primaryLabel,
        segment.secondaryLabel ?? "",
        segment.repoName ?? "",
        segment.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
    ]
        .map {
            $0
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
}

private func isBreakSegment(_ segment: TimelineSegment) -> Bool {
    segment.appName == "Driftly" && segment.primaryLabel.lowercased().contains("break")
}

private func derivedRepoName(fromPath path: String) -> String? {
    let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents.filter { $0 != "/" }
    if let projectsIndex = components.firstIndex(where: { $0 == "ai-projects" || $0 == "projects" || $0 == "src" }),
       components.indices.contains(projectsIndex + 1) {
        return components[projectsIndex + 1]
    }
    return components.last(where: { !$0.contains(".") })
}

private func relativeDisplayPath(_ path: String, repoName: String?) -> String {
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    guard let repoName, let range = normalized.range(of: "/\(repoName)/") else {
        return URL(fileURLWithPath: normalized).lastPathComponent
    }
    return String(normalized[range.upperBound...])
}

private func normalizedHost(_ host: String?) -> String? {
    guard let host = host?.lowercased(), !host.isEmpty else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}

private func isFilePath(_ value: String) -> Bool {
    let path = URL(fileURLWithPath: value).standardizedFileURL.path
    return path.contains(".") && !path.hasSuffix("/")
}

private func extractLikelyFilePath(fromWindowTitle title: String) -> String? {
    let candidates = title.split(separator: " ").map(String.init)
    for candidate in candidates.reversed() where candidate.contains("/") && candidate.contains(".") {
        return URL(fileURLWithPath: candidate).standardizedFileURL.path
    }
    return nil
}

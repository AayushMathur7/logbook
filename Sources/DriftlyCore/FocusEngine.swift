import Foundation

public enum FocusEngine {
    public static func currentSnapshot(
        events: [ActivityEvent],
        sessions: [WorkSession],
        intent: FocusIntent?,
        now: Date = Date()
    ) -> FocusSnapshot {
        let sortedEvents = events.sorted { $0.occurredAt < $1.occurredAt }
        guard let lastEvent = sortedEvents.last else {
            return FocusSnapshot.empty
        }
        
        let currentSession = sessions.last
        let currentApp = sortedEvents.reversed().compactMap(\.appName).first
        let currentTitle = sortedEvents.reversed().compactMap(\.windowTitle).first
        let recentWindowStart = max(lastEvent.occurredAt.addingTimeInterval(-18 * 60), sortedEvents.first?.occurredAt ?? lastEvent.occurredAt)
        let recentEvents = sortedEvents.filter { $0.occurredAt >= recentWindowStart }
        let recentApps = orderedUnique(recentEvents.compactMap(\.appName))
        let recentCommands = Array(recentEvents.compactMap(\.command).suffix(3))
        let switchCount = recentEvents.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count
        let minutesObserved = max(Int(lastEvent.occurredAt.timeIntervalSince(recentWindowStart) / 60), 1)
        let evidence = makeEvidence(
            currentApp: currentApp,
            currentTitle: currentTitle,
            recentApps: recentApps,
            recentCommands: recentCommands,
            switchCount: switchCount,
            lastEventAt: lastEvent.occurredAt,
            now: now
        )
        
        if now.timeIntervalSince(lastEvent.occurredAt) > 8 * 60 {
            let idleHeadline: String
            let idleGuidance: String
            if let intent {
                idleHeadline = "You stepped away from \(intent.title)."
                idleGuidance = "When you come back, reopen the last context instead of starting cold."
            } else {
                idleHeadline = "No recent activity."
                idleGuidance = "Set a focus target when you're ready to start so Driftly can detect drift."
            }
            
            return FocusSnapshot(
                intent: intent,
                status: .idle,
                headline: idleHeadline,
                guidance: idleGuidance,
                confidence: 0.92,
                minutesObserved: minutesObserved,
                contextSwitches: switchCount,
                currentApp: currentApp,
                currentWindowTitle: currentTitle,
                currentContextLabel: currentSession?.contextLabel,
                lastEventAt: lastEvent.occurredAt,
                recentApps: recentApps,
                recentCommands: recentCommands,
                evidence: evidence,
                supportSignals: [],
                driftSignals: []
            )
        }
        
        guard let intent, !intent.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FocusSnapshot(
                intent: nil,
                status: .awaitingIntent,
                headline: currentTitle ?? currentSession?.contextLabel ?? "You're active, but Driftly doesn't know what you're protecting.",
                guidance: "Set one focus target. Then Driftly can tell you whether your current behavior supports it or drifts away from it.",
                confidence: 0.66,
                minutesObserved: minutesObserved,
                contextSwitches: switchCount,
                currentApp: currentApp,
                currentWindowTitle: currentTitle,
                currentContextLabel: currentSession?.contextLabel,
                lastEventAt: lastEvent.occurredAt,
                recentApps: recentApps,
                recentCommands: recentCommands,
                evidence: evidence,
                supportSignals: [],
                driftSignals: []
            )
        }
        
        let intentTokens = normalizedTokens(from: intent.title)
        let corpus = corpusStrings(for: recentEvents, currentSession: currentSession)
        let matchedTokens = intentTokens.filter { token in
            corpus.contains(where: { $0.contains(token) })
        }
        let supportSignals = makeSupportSignals(
            intentTitle: intent.title,
            matchedTokens: matchedTokens,
            recentApps: recentApps,
            currentTitle: currentTitle,
            currentSession: currentSession
        )
        let driftSignals = makeDriftSignals(
            recentApps: recentApps,
            recentEvents: recentEvents,
            matchedTokens: matchedTokens,
            switchCount: switchCount
        )
        
        let browserHeavy = recentApps.contains(where: isBrowserApp(_:))
        let fragmented = switchCount >= 5 || recentApps.count >= 4
        let distractionHeavy = !driftSignals.isEmpty
        let strongMatch = matchedTokens.count >= max(1, min(2, intentTokens.count))
        
        let status: FocusStatus
        let headline: String
        let guidance: String
        let confidence: Double
        
        if strongMatch && !fragmented && !distractionHeavy {
            status = .onTask
            headline = "You're still on \(intent.title)."
            guidance = "Stay in this thread. Avoid opening a second browser loop unless it directly advances the task."
            confidence = boundedConfidence(base: 0.88, supportSignals: supportSignals.count, driftSignals: driftSignals.count)
        } else if !matchedTokens.isEmpty && (browserHeavy || recentApps.count <= 2) {
            status = .support
            headline = "This looks like support work for \(intent.title)."
            guidance = "This is probably still useful, but put a time box on it so research does not replace execution."
            confidence = boundedConfidence(base: 0.76, supportSignals: supportSignals.count, driftSignals: driftSignals.count)
        } else if fragmented {
            status = .fragmented
            headline = "Your attention is splitting away from \(intent.title)."
            guidance = "Close one branch of activity and return to the main thread. Fragmentation is usually where momentum dies."
            confidence = boundedConfidence(base: 0.8, supportSignals: supportSignals.count, driftSignals: driftSignals.count + 1)
        } else {
            status = .drifting
            headline = "You're probably off the intended thread."
            guidance = "Reopen the main artifact for \(intent.title) and take one concrete next action inside it."
            confidence = boundedConfidence(base: 0.82, supportSignals: supportSignals.count, driftSignals: driftSignals.count + 1)
        }
        
        return FocusSnapshot(
            intent: intent,
            status: status,
            headline: headline,
            guidance: guidance,
            confidence: confidence,
            minutesObserved: minutesObserved,
            contextSwitches: switchCount,
            currentApp: currentApp,
            currentWindowTitle: currentTitle,
            currentContextLabel: currentSession?.contextLabel,
            lastEventAt: lastEvent.occurredAt,
            recentApps: recentApps,
            recentCommands: recentCommands,
            evidence: evidence,
            supportSignals: supportSignals,
            driftSignals: driftSignals
        )
    }
    
    public static func suggestions(from sessions: [WorkSession], limit: Int = 5) -> [FocusSuggestion] {
        let grouped = Dictionary(grouping: sessions) { session in
            threadKey(for: session)
        }
        
        let suggestions = grouped.values.compactMap { bucket -> FocusSuggestion? in
            let sorted = bucket.sorted { $0.startAt < $1.startAt }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            let title = displayTitle(for: first)
            guard !title.isEmpty else { return nil }
            
            let minutes = max(Int(sorted.reduce(0) { $0 + $1.duration } / 60), 1)
            let apps = orderedUnique(sorted.flatMap(\.appNames))
            let subtitle = "\(minutes)m today • \(apps.prefix(2).joined(separator: " + "))"
            return FocusSuggestion(
                id: "\(threadKey(for: first))-\(last.endAt.timeIntervalSince1970)",
                title: title,
                subtitle: subtitle,
                minutes: minutes,
                lastTouchedAt: last.endAt,
                apps: apps
            )
        }
        
        return suggestions
            .sorted {
                if $0.lastTouchedAt == $1.lastTouchedAt {
                    return $0.minutes > $1.minutes
                }
                return $0.lastTouchedAt > $1.lastTouchedAt
            }
            .prefix(limit)
            .map { $0 }
    }
    
    public static func reviewBlocks(
        from sessions: [WorkSession],
        intent: FocusIntent?,
        now: Date = Date()
    ) -> [FocusReviewBlock] {
        let sorted = sessions.sorted { $0.startAt < $1.startAt }
        guard let first = sorted.first else { return [] }
        
        var groups: [[WorkSession]] = [[first]]
        
        for session in sorted.dropFirst() {
            guard var lastGroup = groups.popLast(), let previous = lastGroup.last else {
                groups.append([session])
                continue
            }
            
            let gap = session.startAt.timeIntervalSince(previous.endAt)
            if gap <= 12 * 60 && threadKey(for: session) == threadKey(for: previous) {
                lastGroup.append(session)
                groups.append(lastGroup)
            } else {
                groups.append(lastGroup)
                groups.append([session])
            }
        }
        
        return groups.reversed().compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            let title = displayTitle(for: first)
            let apps = orderedUnique(group.flatMap(\.appNames))
            let commands = group.flatMap(\.commands)
            let drifty = apps.count >= 4 || group.reduce(0) { $0 + $1.eventCount } <= 3
            let active = now.timeIntervalSince(last.endAt) <= 10 * 60
            let intentMatch = matchesIntent(title: title, intent: intent)
            let state: FocusReviewState
            
            if active && intentMatch {
                state = .active
            } else if drifty {
                state = .drift
            } else if max(Int(group.reduce(0) { $0 + $1.duration } / 60), 1) >= 15 || !commands.isEmpty {
                state = .solid
            } else {
                state = .paused
            }
            
            var evidence: [String] = []
            if !apps.isEmpty {
                evidence.append("Apps: \(apps.prefix(3).joined(separator: ", "))")
            }
            if let command = commands.last {
                evidence.append("Last command: \(command)")
            }
            if let windowTitle = group.flatMap(\.events).compactMap(\.windowTitle).last {
                evidence.append("Window: \(windowTitle)")
            }
            
            let minutes = max(Int(last.endAt.timeIntervalSince(first.startAt) / 60), 1)
            let summary = "\(minutes)m • \(apps.prefix(2).joined(separator: " + "))"
            
            return FocusReviewBlock(
                id: "\(threadKey(for: first))-\(first.startAt.timeIntervalSince1970)-\(last.endAt.timeIntervalSince1970)",
                title: title,
                startAt: first.startAt,
                endAt: last.endAt,
                state: state,
                summary: summary,
                apps: apps,
                evidence: evidence,
                sessions: group
            )
        }
    }
    
    public static func dayStats(from blocks: [FocusReviewBlock], snapshot: FocusSnapshot) -> FocusDayStats {
        guard !blocks.isEmpty else { return .empty }
        
        var focused = 0
        var support = 0
        var drift = 0
        var openLoops = 0
        var longestSolid = 0
        
        for block in blocks {
            let minutes = max(Int(block.duration / 60), 1)
            switch block.state {
            case .active, .solid:
                focused += minutes
                longestSolid = max(longestSolid, minutes)
            case .drift:
                drift += minutes
            case .paused:
                openLoops += 1
            }
        }
        
        if snapshot.status == .support {
            support += max(snapshot.minutesObserved, 1)
        }
        
        return FocusDayStats(
            focusedMinutes: focused,
            supportMinutes: support,
            driftMinutes: drift,
            openLoops: openLoops,
            longestSolidBlockMinutes: longestSolid
        )
    }
    
    public static func dailyNarrative(
        blocks: [FocusReviewBlock],
        snapshot: FocusSnapshot
    ) -> String {
        guard !blocks.isEmpty else {
            return "Set one focus target and leave Driftly running. The product becomes useful once it can compare intention with actual behavior."
        }
        
        let topBlocks = blocks.prefix(3).map { block in
            "\(block.title) (\(max(Int(block.duration / 60), 1))m, \(block.state.title.lowercased()))"
        }
        
        switch snapshot.status {
        case .onTask:
            return "You have a live thread underway. Main blocks so far: \(topBlocks.joined(separator: ", "))."
        case .support:
            return "You are still near the work, but the current block looks supportive rather than directly executable. Main blocks so far: \(topBlocks.joined(separator: ", "))."
        case .drifting, .fragmented:
            return "The main risk today is continuity loss. Main blocks so far: \(topBlocks.joined(separator: ", "))."
        case .awaitingIntent:
            return "You have enough evidence to infer recent threads, but not enough to judge focus without an explicit target. Recent blocks: \(topBlocks.joined(separator: ", "))."
        case .idle:
            return "You stepped away. Recent blocks before that: \(topBlocks.joined(separator: ", "))."
        }
    }
}

private extension FocusEngine {
    static func makeEvidence(
        currentApp: String?,
        currentTitle: String?,
        recentApps: [String],
        recentCommands: [String],
        switchCount: Int,
        lastEventAt: Date,
        now: Date
    ) -> [String] {
        var evidence: [String] = []
        
        if let currentApp {
            evidence.append("Current app: \(currentApp)")
        }
        if let currentTitle, !currentTitle.isEmpty {
            evidence.append("Current window: \(currentTitle)")
        }
        if !recentApps.isEmpty {
            evidence.append("Recent apps: \(recentApps.joined(separator: ", "))")
        }
        if !recentCommands.isEmpty {
            evidence.append("Recent commands: \(recentCommands.joined(separator: " • "))")
        }
        evidence.append("App switches in the last few minutes: \(switchCount)")
        evidence.append("Last signal: \(ActivityFormatting.relativeDateTime.localizedString(for: lastEventAt, relativeTo: now))")
        return evidence
    }
    
    static func makeSupportSignals(
        intentTitle: String,
        matchedTokens: [String],
        recentApps: [String],
        currentTitle: String?,
        currentSession: WorkSession?
    ) -> [String] {
        var signals: [String] = []
        if !matchedTokens.isEmpty {
            signals.append("Recent context still matches words from '\(intentTitle)'.")
        }
        if recentApps.contains(where: isBrowserApp(_:)) {
            signals.append("A browser is active, which often means research or lookup work.")
        }
        if let currentTitle, currentTitle.localizedCaseInsensitiveContains(intentTitle) {
            signals.append("The current window title explicitly references the intended work.")
        }
        if let currentSession, currentSession.primaryAppName.lowercased().contains("notes") || currentSession.primaryAppName.lowercased().contains("cursor") {
            signals.append("The current session is anchored in a creation tool rather than a passive viewer.")
        }
        return orderedUnique(signals)
    }
    
    static func makeDriftSignals(
        recentApps: [String],
        recentEvents: [ActivityEvent],
        matchedTokens: [String],
        switchCount: Int
    ) -> [String] {
        let distractionTokens = [
            "youtube", "twitter", "x.com", "telegram", "reddit",
            "instagram", "netflix", "prime video", "discord"
        ]
        
        let corpus = corpusStrings(for: recentEvents, currentSession: nil)
        var signals: [String] = []
        
        let matchedDistractions = distractionTokens.filter { token in
            corpus.contains(where: { $0.contains(token) })
        }
        
        if !matchedDistractions.isEmpty && matchedTokens.isEmpty {
            signals.append("Recent context includes likely distraction surfaces: \(matchedDistractions.joined(separator: ", ")).")
        }
        if switchCount >= 5 {
            signals.append("High app switching suggests attention fragmentation rather than a single stable thread.")
        }
        if recentApps.count >= 4 {
            signals.append("Too many distinct apps appeared in one short window.")
        }
        
        return orderedUnique(signals)
    }
    
    static func corpusStrings(for events: [ActivityEvent], currentSession: WorkSession?) -> [String] {
        orderedUnique(
            events.flatMap { event in
                [
                    event.appName?.lowercased(),
                    event.bundleID?.lowercased(),
                    event.windowTitle?.lowercased(),
                    event.resourceTitle?.lowercased(),
                    event.resourceURL?.lowercased(),
                    event.domain?.lowercased(),
                    event.noteText?.lowercased(),
                    event.command?.lowercased(),
                    event.path.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() },
                    event.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() },
                ]
            } + [currentSession?.contextLabel.lowercased()]
        )
    }
    
    static func boundedConfidence(base: Double, supportSignals: Int, driftSignals: Int) -> Double {
        min(max(base + (Double(supportSignals) * 0.03) - (Double(driftSignals) * 0.04), 0.52), 0.96)
    }
    
    static func matchesIntent(title: String, intent: FocusIntent?) -> Bool {
        guard let intent else { return false }
        let tokens = normalizedTokens(from: intent.title)
        let haystack = title.lowercased()
        return tokens.contains { haystack.contains($0) }
    }
    
    static func normalizedTokens(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "and", "for", "with", "into", "from", "that", "this", "work", "task", "focus", "on"]
        let cleaned = text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        
        return orderedUnique(
            cleaned
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        )
    }
    
    static func threadKey(for session: WorkSession) -> String {
        if let workingDirectory = session.events.compactMap(\.workingDirectory).last, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).lastPathComponent.lowercased()
        }
        
        let cleaned = displayTitle(for: session).lowercased()
        return cleaned.isEmpty ? (session.appNames.first ?? "unknown").lowercased() : cleaned
    }
    
    static func displayTitle(for session: WorkSession) -> String {
        let label = session.contextLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty, !isGenericLabel(label) {
            return label
        }
        return session.primaryAppName
    }
    
    static func isGenericLabel(_ value: String) -> Bool {
        let generic = ["google chrome", "safari", "cursor", "terminal", "codex", "unknown context", "finder"]
        return generic.contains(value.lowercased())
    }
    
    static func isBrowserApp(_ app: String) -> Bool {
        let browsers = ["chrome", "safari", "arc", "firefox", "edge", "brave"]
        return browsers.contains { app.lowercased().contains($0) }
    }
    
    static func orderedUnique(_ values: [String?]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { $0 }.filter { seen.insert($0).inserted }
    }
    
    static func orderedUnique(_ values: [String]) -> [String] {
        orderedUnique(values.map(Optional.some))
    }
}

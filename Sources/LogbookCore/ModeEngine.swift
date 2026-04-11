import Foundation

public enum ModeEngine {
    public static func snapshot(events: [ActivityEvent], now: Date = Date()) -> ModeSnapshot {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard let lastEvent = sorted.last else {
            return .empty
        }
        
        let currentWindowStart = lastEvent.occurredAt.addingTimeInterval(-12 * 60)
        let previousWindowStart = currentWindowStart.addingTimeInterval(-12 * 60)
        let currentEvents = sorted.filter { $0.occurredAt >= currentWindowStart }
        let previousEvents = sorted.filter { $0.occurredAt >= previousWindowStart && $0.occurredAt < currentWindowStart }
        
        let currentClassification = classify(events: currentEvents)
        let previousClassification = classify(events: previousEvents)
        
        let shift: String?
        if previousEvents.isEmpty || previousClassification.mode == currentClassification.mode {
            shift = nil
        } else {
            shift = "Shifted from \(previousClassification.mode.title.lowercased()) into \(currentClassification.mode.title.lowercased())."
        }
        
        return ModeSnapshot(
            mode: currentClassification.mode,
            summary: currentClassification.summary,
            why: currentClassification.why,
            evidence: currentClassification.evidence,
            recentShift: shift,
            apps: currentClassification.apps,
            lastUpdatedAt: lastEvent.occurredAt
        )
    }
}

private extension ModeEngine {
    struct Classification {
        let mode: WorkMode
        let summary: String
        let why: String
        let evidence: [String]
        let apps: [String]
    }
    
    static func classify(events: [ActivityEvent]) -> Classification {
        guard !events.isEmpty else {
            return Classification(
                mode: .mixed,
                summary: "Not enough activity to infer a mode.",
                why: "The recent window is too thin to classify.",
                evidence: [],
                apps: []
            )
        }
        
        let apps = orderedUnique(events.compactMap(\.appName))
        let appCounts = orderedCounts(from: events.compactMap(\.appName))
        let titles = events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)
        let titleBlob = titles.joined(separator: " ").lowercased()
        let lastApp = events.last?.appName ?? appCounts.first?.key
        let lastTitle = (events.last?.resourceTitle ?? events.last?.windowTitle ?? "").lowercased()
        let switchCount = events.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count
        let browserHeavy = apps.contains(where: isBrowserApp(_:))
        let hasBuilderLoop = containsAny(apps, ["Codex", "Cursor"]) && browserHeavy
        let hasCoordination = containsAny(apps, ["Telegram", "Messages", "WhatsApp", "Slack"])
        let hasSetup = containsAny(apps, ["System Settings", "universalAccessAuthWarn"])
        let hasMedia = titleBlob.contains("youtube") || titleBlob.contains("spotify") || titleBlob.contains("netflix")
        let foregroundMedia = lastTitle.contains("youtube") || lastTitle.contains("spotify") || lastTitle.contains("netflix")
        let currentAppIsBrowser = lastApp.map(isBrowserApp(_:)) ?? false
        let hasComparison = titleBlob.contains("dayflow") || titleBlob.contains("github") || titleBlob.contains("search") || titleBlob.contains("hn") || titleBlob.contains("hacker news")
        
        if hasSetup {
            return Classification(
                mode: .setup,
                summary: "You are in setup mode.",
                why: "System settings and permission-related surfaces are active right now.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if foregroundMedia && currentAppIsBrowser && !hasComparison {
            let mode: WorkMode = switchCount <= 3 ? .decompressing : .drifting
            let summary = mode == .decompressing
                ? "The current foreground looks like passive media."
                : "You are bouncing between work and passive media."
            let why = mode == .decompressing
                ? "The foreground window is media-heavy right now, so earlier build activity should not dominate the label."
                : "Media is in the foreground, but the recent window is still noisy from nearby work switches."
            return Classification(
                mode: mode,
                summary: summary,
                why: why,
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if hasMedia && apps.count <= 2 && switchCount <= 2 {
            return Classification(
                mode: .decompressing,
                summary: "This looks like passive media, not active work.",
                why: "The recent window is dominated by media cues with a stable foreground app.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if hasBuilderLoop && hasComparison {
            return Classification(
                mode: .comparing,
                summary: "You are bouncing between building and comparison research.",
                why: "Codex/Cursor are active, but the browser context still looks dominated by reference or adjacent-product pages.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if hasBuilderLoop {
            return Classification(
                mode: .building,
                summary: "You are in a live build loop.",
                why: "The recent sequence is anchored in Codex, Cursor, and browser verification rather than passive browsing.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if browserHeavy && hasComparison {
            return Classification(
                mode: .researching,
                summary: "You are in active research mode.",
                why: "The browser dominates the recent window and the open titles look like lookup, comparison, or exploration rather than idle consumption.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if hasCoordination {
            return Classification(
                mode: .coordinating,
                summary: "You are coordinating across chats and tools.",
                why: "Messaging surfaces have entered the recent window and are pulling attention away from a single working surface.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        if hasMedia || switchCount >= 6 || appCounts.count >= 4 {
            return Classification(
                mode: .drifting,
                summary: "The current window looks fragmented.",
                why: "There are too many switches or entertainment-like surfaces in one short block to call this a stable work mode.",
                evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
                apps: apps
            )
        }
        
        return Classification(
            mode: .mixed,
            summary: "The current mode is mixed.",
            why: "The recent evidence does not support a sharper classification yet.",
            evidence: makeEvidence(apps: apps, titles: titles, switchCount: switchCount),
            apps: apps
        )
    }
    
    static func makeEvidence(apps: [String], titles: [String], switchCount: Int) -> [String] {
        var evidence: [String] = []
        if !apps.isEmpty {
            evidence.append("Apps: \(apps.prefix(3).joined(separator: ", "))")
        }
        if let title = titles.last {
            evidence.append("Window: \(truncate(title, limit: 80))")
        }
        evidence.append("Recent app switches: \(switchCount)")
        return evidence
    }
    
    static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
    
    static func orderedCounts(from values: [String]) -> [(key: String, count: Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.key < $1.key }
                return $0.count > $1.count
            }
    }
    
    static func containsAny(_ values: [String], _ required: [String]) -> Bool {
        let set = Set(values)
        return required.contains(where: { set.contains($0) })
    }
    
    static func isBrowserApp(_ app: String) -> Bool {
        let lower = app.lowercased()
        return lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("firefox") || lower.contains("brave")
    }
    
    static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let index = value.index(value.startIndex, offsetBy: limit)
        return "\(value[..<index])…"
    }
}

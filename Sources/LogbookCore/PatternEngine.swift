import Foundation

public enum PatternEngine {
    public static func snapshot(
        events: [ActivityEvent],
        now: Date = Date(),
        windowHours: Int = 24
    ) -> PatternSnapshot {
        let cutoff = now.addingTimeInterval(TimeInterval(-windowHours * 60 * 60))
        let recentEvents = events
            .filter { $0.occurredAt >= cutoff }
            .sorted { $0.occurredAt < $1.occurredAt }
        
        guard !recentEvents.isEmpty else {
            return .empty
        }
        
        let appCounts = orderedCounts(from: recentEvents.compactMap(\.appName))
        let topApps = appCounts.prefix(4).map(\.key)
        let switchCount = recentEvents.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count
        let titleBlob = (recentEvents.compactMap(\.windowTitle) + recentEvents.compactMap(\.resourceTitle) + recentEvents.compactMap(\.domain))
            .joined(separator: " ")
            .lowercased()
        let transitionLoop = dominantLoop(from: recentEvents)
        let switchesPerHour = Double(switchCount) / max(Double(windowHours), 1)
        let distractionApps = appCounts.filter { distractionNames.contains($0.key.lowercased()) }
        
        var observations: [BehaviorPattern] = []
        var driftTriggers: [BehaviorPattern] = []
        
        if containsAll(topApps, required: ["Codex", "Cursor", "Google Chrome"]) {
            observations.append(
                BehaviorPattern(
                    id: "rapid-iteration",
                    title: "Rapid external iteration",
                    detail: "Your default loop is conversation, implementation, and verification. You move between Codex, Cursor, and Chrome instead of staying inside one surface.",
                    tone: .positive
                )
            )
        }
        
        if titleBlob.contains("dayflow") || titleBlob.contains("hacker news") || titleBlob.contains("github") {
            observations.append(
                BehaviorPattern(
                    id: "comparison-mode",
                    title: "Comparison sharpens your taste",
                    detail: "Adjacent products and reference pages show up often enough that comparison looks like part of your design process, not random browsing.",
                    tone: .positive
                )
            )
        }
        
        if switchesPerHour >= 18 {
            observations.append(
                BehaviorPattern(
                    id: "continuity-risk",
                    title: "Continuity loss is the real risk",
                    detail: "Your activity is high, but your switching density is also high. The main danger looks like thread loss, not inactivity.",
                    tone: .caution
                )
            )
        }
        
        if titleBlob.contains("youtube") {
            driftTriggers.append(
                BehaviorPattern(
                    id: "youtube-drift",
                    title: "Passive video is a likely escape hatch",
                    detail: "YouTube appears often enough in the recent window that it should be treated as a common drift surface when work gets harder.",
                    tone: .caution
                )
            )
        }
        
        if !distractionApps.isEmpty {
            let names = distractionApps.prefix(2).map(\.key).joined(separator: " and ")
            driftTriggers.append(
                BehaviorPattern(
                    id: "messaging-drift",
                    title: "Messages and social checks reset the thread",
                    detail: "\(names) show up often enough to matter. The cost is probably the restart after each check, not the check itself.",
                    tone: .caution
                )
            )
        }
        
        if observations.isEmpty {
            observations.append(
                BehaviorPattern(
                    id: "default-pattern",
                    title: "Early pattern signal",
                    detail: "There is enough activity to infer a working style, but not enough stable repetition yet to say something sharper.",
                    tone: .neutral
                )
            )
        }
        
        if driftTriggers.isEmpty {
            driftTriggers.append(
                BehaviorPattern(
                    id: "no-clear-trigger",
                    title: "No single drift trigger dominates",
                    detail: "Recent behavior looks more fragmented than hijacked by one obvious surface. That usually means too many small switches.",
                    tone: .neutral
                )
            )
        }
        
        return PatternSnapshot(
            windowHours: windowHours,
            summary: summaryLine(
                topApps: topApps,
                transitionLoop: transitionLoop,
                switchesPerHour: switchesPerHour,
                titleBlob: titleBlob
            ),
            dominantLoop: transitionLoop,
            primaryRisk: driftTriggers.first?.detail ?? "No primary risk detected.",
            topApps: topApps,
            observations: observations,
            driftTriggers: driftTriggers
        )
    }
}

private extension PatternEngine {
    static let distractionNames: Set<String> = [
        "youtube",
        "telegram",
        "messages",
        "twitter",
        "x",
        "reddit",
        "discord",
        "netflix",
    ]
    
    static func orderedCounts(from values: [String]) -> [(key: String, count: Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted {
                if $0.count == $1.count { return $0.key < $1.key }
                return $0.count > $1.count
            }
    }
    
    static func dominantLoop(from events: [ActivityEvent]) -> String {
        var transitions: [String: Int] = [:]
        var lastApp: String?
        
        for event in events where event.kind == .appActivated {
            guard let app = event.appName else { continue }
            if let lastApp, lastApp != app {
                transitions["\(lastApp) -> \(app)", default: 0] += 1
            }
            lastApp = app
        }
        
        let topPairs = transitions
            .sorted {
                if $0.value == $1.value { return $0.key < $1.key }
                return $0.value > $1.value
            }
            .prefix(3)
            .map(\.key)
        
        if topPairs.contains("Codex -> Google Chrome") && topPairs.contains("Google Chrome -> Codex") {
            if transitions.keys.contains("Codex -> Cursor") || transitions.keys.contains("Cursor -> Codex") {
                return "Codex -> Google Chrome -> Cursor"
            }
            return "Codex -> Google Chrome"
        }
        
        return topPairs.first ?? "No stable loop yet"
    }
    
    static func summaryLine(
        topApps: [String],
        transitionLoop: String,
        switchesPerHour: Double,
        titleBlob: String
    ) -> String {
        let topLine = topApps.prefix(3).joined(separator: ", ")
        let mode: String
        
        if titleBlob.contains("dayflow") || titleBlob.contains("github") {
            mode = "This looks more like product shaping than passive browsing."
        } else if titleBlob.contains("youtube") {
            mode = "This mixes real work with some passive media drift."
        } else {
            mode = "This is active but still noisy."
        }
        
        return "Your last 24 hours were anchored in \(topLine). The dominant loop was \(transitionLoop). \(mode) App switching is running at about \(Int(round(switchesPerHour))) changes per hour."
    }
    
    static func containsAll(_ haystack: [String], required: [String]) -> Bool {
        let set = Set(haystack)
        return required.allSatisfy { set.contains($0) }
    }
}

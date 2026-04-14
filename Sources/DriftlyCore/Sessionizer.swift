import Foundation

public enum Sessionizer {
    public static func sessions(from events: [ActivityEvent], gapThreshold: TimeInterval = 10 * 60) -> [WorkSession] {
        let sortedEvents = events.sorted { $0.occurredAt < $1.occurredAt }
        var buckets: [[ActivityEvent]] = []
        var currentBucket: [ActivityEvent] = []

        for event in sortedEvents {
            if ignoredKinds.contains(event.kind) {
                continue
            }

            if boundaryKinds.contains(event.kind) {
                if !currentBucket.isEmpty {
                    buckets.append(currentBucket)
                    currentBucket = []
                }
                continue
            }

            guard let lastEvent = currentBucket.last else {
                currentBucket = [event]
                continue
            }

            let isNewSession = event.occurredAt.timeIntervalSince(lastEvent.occurredAt) > gapThreshold
                || sessionKey(for: event) != sessionKey(for: lastEvent)

            if isNewSession {
                buckets.append(currentBucket)
                currentBucket = [event]
            } else {
                currentBucket.append(event)
            }
        }

        if !currentBucket.isEmpty {
            buckets.append(currentBucket)
        }

        return buckets.compactMap(makeSession)
    }
    
    public static func dailySummary(for sessions: [WorkSession], date: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateStyle = .medium
        dayFormatter.timeStyle = .none
        
        guard !sessions.isEmpty else {
            return "No captured activity for \(dayFormatter.string(from: date)) yet."
        }
        
        let totalMinutes = sessions.reduce(0) { $0 + max(Int($1.duration / 60), 1) }
        let commandCount = sessions.reduce(0) { $0 + $1.commands.count }
        
        var lines: [String] = []
        lines.append("Summary for \(dayFormatter.string(from: date))")
        lines.append("")
        lines.append("Captured \(sessions.count) session\(sessions.count == 1 ? "" : "s") across roughly \(totalMinutes) minutes.")
        
        if commandCount > 0 {
            lines.append("Imported \(commandCount) terminal command\(commandCount == 1 ? "" : "s").")
        }
        
        lines.append("")
        lines.append("Main sessions:")
        
        for session in sessions.prefix(5) {
            let window = ActivityFormatting.sessionTime.string(from: session.startAt, to: session.endAt)
            lines.append("- \(window): \(session.contextLabel) (\(session.shortSummary))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private static func makeSession(events: [ActivityEvent]) -> WorkSession? {
        guard let first = events.first, let last = events.last else {
            return nil
        }
        
        let appNames = orderedUniqueValues(events.compactMap(\.appName))
        let commands = events.compactMap(\.command)
        let label = inferContextLabel(from: events) ?? appNames.first ?? "Unknown Context"
        
        return WorkSession(
            id: "\(first.id)-\(last.id)",
            startAt: first.occurredAt,
            endAt: last.occurredAt,
            contextLabel: label,
            appNames: appNames,
            commands: commands,
            eventCount: events.count,
            events: events
        )
    }
    
    private static func sessionKey(for event: ActivityEvent) -> String {
        if let cwd = event.workingDirectory, !cwd.isEmpty {
            return "cwd:\(URL(fileURLWithPath: cwd).lastPathComponent.lowercased())"
        }

        if let path = event.path, !path.isEmpty {
            return "path:\(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent.lowercased())"
        }

        if let domain = event.domain, !domain.isEmpty {
            return "domain:\(domain.lowercased())"
        }
        
        if let title = inferLabel(from: event.resourceTitle) ?? inferLabel(from: event.windowTitle) {
            return "title:\(title.lowercased())|\(event.bundleID ?? event.appName ?? "unknown")"
        }
        
        return event.bundleID ?? event.appName ?? "unknown"
    }
    
    private static func inferContextLabel(from events: [ActivityEvent]) -> String? {
        let cwd = events.compactMap(\.workingDirectory).last
        if let cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        if let path = events.compactMap(\.path).last, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        if let resourceTitle = orderedUniqueValues(events.compactMap(\.resourceTitle).compactMap(inferLabel(from:))).first {
            return resourceTitle
        }

        if let domain = events.compactMap(\.domain).last, !domain.isEmpty {
            return domain
        }
        
        let titles = events.compactMap(\.windowTitle).compactMap(inferLabel(from:))
        return orderedUniqueValues(titles).first
    }
    
    private static func inferLabel(from rawTitle: String?) -> String? {
        guard let rawTitle else { return nil }
        
        let separators = [" — ", " – ", " - ", " · "]
        for separator in separators {
            let parts = rawTitle.components(separatedBy: separator)
            if let first = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
                return first
            }
        }
        
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func orderedUniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static let ignoredKinds: Set<ActivityKind> = [
        .capturePaused,
        .captureResumed,
    ]

    private static let boundaryKinds: Set<ActivityKind> = [
        .userIdle,
        .userResumed,
        .systemWoke,
        .systemSlept,
    ]
}

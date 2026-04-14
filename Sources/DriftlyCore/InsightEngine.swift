import Foundation

public enum InsightEngine {
    public static func recentWindows(events: [ActivityEvent], now: Date = Date(), intervalMinutes: Int = 5, limit: Int = 6) -> [InsightWindow] {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard let lastEvent = sorted.last else { return [] }
        
        let interval = TimeInterval(intervalMinutes * 60)
        let end = lastEvent.occurredAt.timeIntervalSinceReferenceDate
        let start = max(sorted.first?.occurredAt.timeIntervalSinceReferenceDate ?? end, end - TimeInterval(limit * intervalMinutes * 60))
        
        var windows: [InsightWindow] = []
        var bucketEnd = end
        
        while bucketEnd > start && windows.count < limit {
            let bucketStart = bucketEnd - interval
            let bucketEvents = sorted.filter {
                let t = $0.occurredAt.timeIntervalSinceReferenceDate
                return t > bucketStart && t <= bucketEnd
            }
            if !bucketEvents.isEmpty {
                let generatedAt = bucketEvents.last?.occurredAt ?? Date(timeIntervalSinceReferenceDate: bucketEnd)
                let bucketID = "\(Int(bucketEnd / interval))"
                windows.append(
                    InsightWindow(
                        id: bucketID,
                        startAt: Date(timeIntervalSinceReferenceDate: bucketStart),
                        endAt: Date(timeIntervalSinceReferenceDate: bucketEnd),
                        generatedAt: generatedAt,
                        events: bucketEvents
                    )
                )
            }
            bucketEnd -= interval
        }
        
        return windows
    }

    public static func currentInsight(events: [ActivityEvent], now: Date = Date()) -> InsightCard {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard let lastEvent = sorted.last else {
            return InsightCard(
                id: "empty",
                generatedAt: now,
                headline: "Not enough activity to say what you’ve been doing yet.",
                focus: .mixed,
                why: "Leave Driftly running a little longer so it has a recent block to summarize."
            )
        }
        
        let windowStart = lastEvent.occurredAt.addingTimeInterval(-8 * 60)
        let recent = sorted.filter { $0.occurredAt >= windowStart }
        let apps = orderedUnique(recent.compactMap(\.appName))
        let titles = recent.compactMap(\.windowTitle) + recent.compactMap(\.resourceTitle)
        let titleBlob = titles.joined(separator: " ").lowercased()
        let switchCount = recent.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count
        let browserHeavy = apps.contains(where: isBrowserApp(_:))
        let hasBuilderLoop = containsAny(apps, ["Codex", "Cursor"]) && browserHeavy
        let hasMedia = titleBlob.contains("youtube") || titleBlob.contains("spotify") || titleBlob.contains("netflix")
        let hasComparison = titleBlob.contains("dayflow") || titleBlob.contains("github") || titleBlob.contains("search") || titleBlob.contains("hacker news")
        let hasCoordination = containsAny(apps, ["Telegram", "Messages", "WhatsApp", "Slack"])
        let foregroundTitle = titles.last?.lowercased() ?? ""
        
        let headline: String
        let focus: FocusLabel
        let why: String
        
        if (foregroundTitle.contains("youtube") || foregroundTitle.contains("spotify") || foregroundTitle.contains("netflix")) && browserHeavy {
            if hasBuilderLoop || switchCount >= 3 {
                headline = "You’ve been mixing work with passive media."
                focus = .scattered
                why = "Media is in the foreground, but recent activity still contains nearby work switches."
            } else {
                headline = "You’ve been watching or listening, not really working."
                focus = .scattered
                why = "The recent window is dominated by media in the foreground."
            }
        } else if hasBuilderLoop && hasComparison {
            headline = "You’ve been comparing ideas while building."
            focus = switchCount >= 5 ? .mixed : .focused
            why = "Codex, Cursor, and browser reference pages are all active in the same recent block."
        } else if hasBuilderLoop {
            headline = "You’ve been in a build loop."
            focus = switchCount >= 5 ? .mixed : .focused
            why = "Recent activity is anchored in Codex, Cursor, and browser verification rather than passive browsing."
        } else if browserHeavy && hasComparison {
            headline = "You’ve been researching and comparing."
            focus = switchCount >= 5 ? .mixed : .focused
            why = "The browser dominates the recent window and the open titles look exploratory rather than idle."
        } else if hasCoordination {
            headline = "You’ve been coordinating across chats and tools."
            focus = .mixed
            why = "Messaging surfaces are active, which usually means attention is split across coordination work."
        } else if switchCount >= 6 || apps.count >= 4 || hasMedia {
            headline = "You’ve been bouncing between too many things."
            focus = .scattered
            why = "There are too many switches or entertainment-like surfaces in one short block to call this stable."
        } else {
            headline = "You’ve been in a mixed work block."
            focus = .mixed
            why = "The recent evidence is active, but not clear enough to support a sharper read."
        }
        
        return InsightCard(
            id: "\(Int(lastEvent.occurredAt.timeIntervalSince1970 / 300))",
            generatedAt: lastEvent.occurredAt,
            headline: headline,
            focus: focus,
            why: why
        )
    }
    
    public static func recentInsights(events: [ActivityEvent], now: Date = Date(), intervalMinutes: Int = 5, limit: Int = 6) -> [InsightCard] {
        recentWindows(events: events, now: now, intervalMinutes: intervalMinutes, limit: limit).map {
            heuristicInsight(for: $0, now: now)
        }
    }
}

private extension InsightEngine {
    static func heuristicInsight(for window: InsightWindow, now: Date = Date()) -> InsightCard {
        let base = currentInsight(events: window.events, now: now)
        return InsightCard(
            id: window.id,
            generatedAt: window.generatedAt,
            headline: base.headline,
            focus: base.focus,
            why: base.why
        )
    }

    static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
    
    static func containsAny(_ values: [String], _ required: [String]) -> Bool {
        let set = Set(values)
        return required.contains(where: { set.contains($0) })
    }
    
    static func isBrowserApp(_ app: String) -> Bool {
        let lower = app.lowercased()
        return lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("firefox") || lower.contains("brave")
    }
}

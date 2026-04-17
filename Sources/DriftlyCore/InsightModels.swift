import Foundation

public enum FocusLabel: String, Codable, CaseIterable {
    case focused
    case mixed
    case scattered
    
    public var title: String {
        rawValue.capitalized
    }
}

public struct InsightCard: Identifiable, Hashable {
    public let id: String
    public let generatedAt: Date
    public let headline: String
    public let focus: FocusLabel
    public let why: String
    
    public init(id: String, generatedAt: Date, headline: String, focus: FocusLabel, why: String) {
        self.id = id
        self.generatedAt = generatedAt
        self.headline = headline
        self.focus = focus
        self.why = why
    }

}

public struct InsightWindow: Identifiable, Hashable {
    public let id: String
    public let startAt: Date
    public let endAt: Date
    public let generatedAt: Date
    public let events: [ActivityEvent]
    
    public init(id: String, startAt: Date, endAt: Date, generatedAt: Date, events: [ActivityEvent]) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.generatedAt = generatedAt
        self.events = events
    }
}

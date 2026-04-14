import Foundation

public enum PatternTone: String, Codable, CaseIterable {
    case positive
    case caution
    case neutral
}

public struct BehaviorPattern: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    public let tone: PatternTone
    
    public init(id: String, title: String, detail: String, tone: PatternTone) {
        self.id = id
        self.title = title
        self.detail = detail
        self.tone = tone
    }
}

public struct PatternSnapshot: Hashable {
    public let windowHours: Int
    public let summary: String
    public let dominantLoop: String
    public let primaryRisk: String
    public let topApps: [String]
    public let observations: [BehaviorPattern]
    public let driftTriggers: [BehaviorPattern]
    
    public init(
        windowHours: Int,
        summary: String,
        dominantLoop: String,
        primaryRisk: String,
        topApps: [String],
        observations: [BehaviorPattern],
        driftTriggers: [BehaviorPattern]
    ) {
        self.windowHours = windowHours
        self.summary = summary
        self.dominantLoop = dominantLoop
        self.primaryRisk = primaryRisk
        self.topApps = topApps
        self.observations = observations
        self.driftTriggers = driftTriggers
    }
    
    public static let empty = PatternSnapshot(
        windowHours: 24,
        summary: "Not enough recent data yet.",
        dominantLoop: "No dominant loop yet.",
        primaryRisk: "No clear risk yet.",
        topApps: [],
        observations: [],
        driftTriggers: []
    )
}

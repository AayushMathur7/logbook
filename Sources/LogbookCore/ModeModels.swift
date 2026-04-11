import Foundation

public enum WorkMode: String, Codable, CaseIterable {
    case building
    case researching
    case comparing
    case coordinating
    case setup
    case decompressing
    case drifting
    case mixed
    
    public var title: String {
        switch self {
        case .building:
            return "Building"
        case .researching:
            return "Researching"
        case .comparing:
            return "Comparing"
        case .coordinating:
            return "Coordinating"
        case .setup:
            return "Setup"
        case .decompressing:
            return "Decompressing"
        case .drifting:
            return "Drifting"
        case .mixed:
            return "Mixed"
        }
    }
}

public struct ModeSnapshot: Hashable {
    public let mode: WorkMode
    public let summary: String
    public let why: String
    public let evidence: [String]
    public let recentShift: String?
    public let apps: [String]
    public let lastUpdatedAt: Date?
    
    public init(
        mode: WorkMode,
        summary: String,
        why: String,
        evidence: [String],
        recentShift: String?,
        apps: [String],
        lastUpdatedAt: Date?
    ) {
        self.mode = mode
        self.summary = summary
        self.why = why
        self.evidence = evidence
        self.recentShift = recentShift
        self.apps = apps
        self.lastUpdatedAt = lastUpdatedAt
    }
    
    public static let empty = ModeSnapshot(
        mode: .mixed,
        summary: "No recent activity yet.",
        why: "Leave Logbook running for a few minutes so it has enough signal to classify the current mode.",
        evidence: [],
        recentShift: nil,
        apps: [],
        lastUpdatedAt: nil
    )
}

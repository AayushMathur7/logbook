import Foundation

public enum ContextNodeKind: String, Codable, CaseIterable {
    case app
    case site
    case repo
    case file
}

public struct ContextNode: Identifiable, Hashable, Codable {
    public let id: String
    public let kind: ContextNodeKind
    public let label: String
    public let normalizedLabel: String
    public let appName: String?
    public let domain: String?
    public let repoName: String?
    public let filePath: String?
    public let firstSeenAt: Date
    public let lastSeenAt: Date

    public init(
        id: String,
        kind: ContextNodeKind,
        label: String,
        normalizedLabel: String,
        appName: String? = nil,
        domain: String? = nil,
        repoName: String? = nil,
        filePath: String? = nil,
        firstSeenAt: Date,
        lastSeenAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.normalizedLabel = normalizedLabel
        self.appName = appName
        self.domain = domain
        self.repoName = repoName
        self.filePath = filePath
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

public struct SessionContextSurface: Hashable, Codable {
    public let sessionID: String
    public let nodeID: String
    public let role: SessionSegmentRole
    public let seconds: Int
    public let share: Double
    public let firstPosition: Int
    public let lastPosition: Int

    public init(
        sessionID: String,
        nodeID: String,
        role: SessionSegmentRole,
        seconds: Int,
        share: Double,
        firstPosition: Int,
        lastPosition: Int
    ) {
        self.sessionID = sessionID
        self.nodeID = nodeID
        self.role = role
        self.seconds = seconds
        self.share = share
        self.firstPosition = firstPosition
        self.lastPosition = lastPosition
    }
}

public struct SessionContextTransition: Hashable, Codable {
    public let sessionID: String
    public let fromNodeID: String
    public let toNodeID: String
    public let relation: String
    public let count: Int
    public let lastSeenAt: Date

    public init(
        sessionID: String,
        fromNodeID: String,
        toNodeID: String,
        relation: String,
        count: Int,
        lastSeenAt: Date
    ) {
        self.sessionID = sessionID
        self.fromNodeID = fromNodeID
        self.toNodeID = toNodeID
        self.relation = relation
        self.count = count
        self.lastSeenAt = lastSeenAt
    }
}

public struct ContextPatternSnapshot: Hashable, Codable {
    public let sessionCount: Int
    public let alignedSurfaces: [String]
    public let driftSurfaces: [String]
    public let commonTransitions: [String]

    public init(
        sessionCount: Int,
        alignedSurfaces: [String],
        driftSurfaces: [String],
        commonTransitions: [String]
    ) {
        self.sessionCount = sessionCount
        self.alignedSurfaces = alignedSurfaces
        self.driftSurfaces = driftSurfaces
        self.commonTransitions = commonTransitions
    }
}

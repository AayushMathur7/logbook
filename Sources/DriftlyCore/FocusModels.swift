import Foundation

public struct FocusIntent: Codable, Hashable {
    public let title: String
    public let startedAt: Date
    
    public init(title: String, startedAt: Date = Date()) {
        self.title = title
        self.startedAt = startedAt
    }
}

public enum FocusStatus: String, Codable, CaseIterable {
    case awaitingIntent
    case onTask
    case support
    case drifting
    case fragmented
    case idle
    
    public var title: String {
        switch self {
        case .awaitingIntent:
            return "Set a target"
        case .onTask:
            return "On task"
        case .support:
            return "Support work"
        case .drifting:
            return "Drifting"
        case .fragmented:
            return "Fragmented"
        case .idle:
            return "Idle"
        }
    }
}

public struct FocusSnapshot: Hashable {
    public let intent: FocusIntent?
    public let status: FocusStatus
    public let headline: String
    public let guidance: String
    public let confidence: Double
    public let minutesObserved: Int
    public let contextSwitches: Int
    public let currentApp: String?
    public let currentWindowTitle: String?
    public let currentContextLabel: String?
    public let lastEventAt: Date?
    public let recentApps: [String]
    public let recentCommands: [String]
    public let evidence: [String]
    public let supportSignals: [String]
    public let driftSignals: [String]
    
    public init(
        intent: FocusIntent?,
        status: FocusStatus,
        headline: String,
        guidance: String,
        confidence: Double,
        minutesObserved: Int,
        contextSwitches: Int,
        currentApp: String?,
        currentWindowTitle: String?,
        currentContextLabel: String?,
        lastEventAt: Date?,
        recentApps: [String],
        recentCommands: [String],
        evidence: [String],
        supportSignals: [String],
        driftSignals: [String]
    ) {
        self.intent = intent
        self.status = status
        self.headline = headline
        self.guidance = guidance
        self.confidence = confidence
        self.minutesObserved = minutesObserved
        self.contextSwitches = contextSwitches
        self.currentApp = currentApp
        self.currentWindowTitle = currentWindowTitle
        self.currentContextLabel = currentContextLabel
        self.lastEventAt = lastEventAt
        self.recentApps = recentApps
        self.recentCommands = recentCommands
        self.evidence = evidence
        self.supportSignals = supportSignals
        self.driftSignals = driftSignals
    }
    
    public static let empty = FocusSnapshot(
        intent: nil,
        status: .awaitingIntent,
        headline: "No captured context yet.",
        guidance: "Grant permissions and leave Driftly running to build focus evidence.",
        confidence: 0,
        minutesObserved: 0,
        contextSwitches: 0,
        currentApp: nil,
        currentWindowTitle: nil,
        currentContextLabel: nil,
        lastEventAt: nil,
        recentApps: [],
        recentCommands: [],
        evidence: [],
        supportSignals: [],
        driftSignals: []
    )
}

public struct FocusSuggestion: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let minutes: Int
    public let lastTouchedAt: Date
    public let apps: [String]
    
    public init(id: String, title: String, subtitle: String, minutes: Int, lastTouchedAt: Date, apps: [String]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.minutes = minutes
        self.lastTouchedAt = lastTouchedAt
        self.apps = apps
    }
}

public enum FocusReviewState: String, Codable, CaseIterable {
    case active
    case solid
    case drift
    case paused
    
    public var title: String {
        switch self {
        case .active:
            return "Active"
        case .solid:
            return "Solid"
        case .drift:
            return "Drifted"
        case .paused:
            return "Paused"
        }
    }
}

public struct FocusReviewBlock: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let startAt: Date
    public let endAt: Date
    public let state: FocusReviewState
    public let summary: String
    public let apps: [String]
    public let evidence: [String]
    public let sessions: [WorkSession]
    
    public init(
        id: String,
        title: String,
        startAt: Date,
        endAt: Date,
        state: FocusReviewState,
        summary: String,
        apps: [String],
        evidence: [String],
        sessions: [WorkSession]
    ) {
        self.id = id
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.state = state
        self.summary = summary
        self.apps = apps
        self.evidence = evidence
        self.sessions = sessions
    }
    
    public var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
}

public struct FocusDayStats: Hashable {
    public let focusedMinutes: Int
    public let supportMinutes: Int
    public let driftMinutes: Int
    public let openLoops: Int
    public let longestSolidBlockMinutes: Int
    
    public init(
        focusedMinutes: Int,
        supportMinutes: Int,
        driftMinutes: Int,
        openLoops: Int,
        longestSolidBlockMinutes: Int
    ) {
        self.focusedMinutes = focusedMinutes
        self.supportMinutes = supportMinutes
        self.driftMinutes = driftMinutes
        self.openLoops = openLoops
        self.longestSolidBlockMinutes = longestSolidBlockMinutes
    }
    
    public static let empty = FocusDayStats(
        focusedMinutes: 0,
        supportMinutes: 0,
        driftMinutes: 0,
        openLoops: 0,
        longestSolidBlockMinutes: 0
    )
}

import Foundation

public enum ActivitySource: String, Codable, CaseIterable {
    case workspace
    case accessibility
    case shell
    case system
    case browser
    case presence
    case manual
    case fileSystem
}

public enum ActivityKind: String, Codable, CaseIterable {
    case appActivated
    case appLaunched
    case appTerminated
    case systemWoke
    case systemSlept
    case windowChanged
    case fileCreated
    case fileModified
    case fileRenamed
    case fileDeleted
    case commandStarted
    case commandFinished
    case tabFocused
    case tabChanged
    case userIdle
    case userResumed
    case clipboardChanged
    case noteAdded
    case sessionPinned
    case capturePaused
    case captureResumed
    case focusGuardPrompted
    case focusGuardRecovered
    case focusGuardSnoozed
    case focusGuardIgnored
}

public extension ActivityKind {
    var isFocusGuardSignal: Bool {
        switch self {
        case .focusGuardPrompted, .focusGuardRecovered, .focusGuardSnoozed, .focusGuardIgnored:
            return true
        default:
            return false
        }
    }
}

public struct ActivityEvent: Identifiable, Codable, Hashable {
    public let id: String
    public let occurredAt: Date
    public let source: ActivitySource
    public let kind: ActivityKind
    public let appName: String?
    public let bundleID: String?
    public let windowTitle: String?
    public let path: String?
    public let resourceTitle: String?
    public let resourceURL: String?
    public let domain: String?
    public let clipboardPreview: String?
    public let noteText: String?
    public let relatedID: String?
    public let command: String?
    public let workingDirectory: String?
    public let commandStartedAt: Date?
    public let commandFinishedAt: Date?
    public let durationMilliseconds: Int?
    public let exitCode: Int?
    
    public init(
        id: String = UUID().uuidString,
        occurredAt: Date,
        source: ActivitySource,
        kind: ActivityKind,
        appName: String? = nil,
        bundleID: String? = nil,
        windowTitle: String? = nil,
        path: String? = nil,
        resourceTitle: String? = nil,
        resourceURL: String? = nil,
        domain: String? = nil,
        clipboardPreview: String? = nil,
        noteText: String? = nil,
        relatedID: String? = nil,
        command: String? = nil,
        workingDirectory: String? = nil,
        commandStartedAt: Date? = nil,
        commandFinishedAt: Date? = nil,
        durationMilliseconds: Int? = nil,
        exitCode: Int? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.source = source
        self.kind = kind
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.path = path
        self.resourceTitle = resourceTitle
        self.resourceURL = resourceURL
        self.domain = domain
        self.clipboardPreview = clipboardPreview
        self.noteText = noteText
        self.relatedID = relatedID
        self.command = command
        self.workingDirectory = workingDirectory
        self.commandStartedAt = commandStartedAt
        self.commandFinishedAt = commandFinishedAt
        self.durationMilliseconds = durationMilliseconds
        self.exitCode = exitCode
    }
}

public struct WorkSession: Identifiable, Hashable {
    public let id: String
    public let startAt: Date
    public let endAt: Date
    public let contextLabel: String
    public let appNames: [String]
    public let commands: [String]
    public let eventCount: Int
    public let events: [ActivityEvent]
    
    public init(
        id: String,
        startAt: Date,
        endAt: Date,
        contextLabel: String,
        appNames: [String],
        commands: [String],
        eventCount: Int,
        events: [ActivityEvent]
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.contextLabel = contextLabel
        self.appNames = appNames
        self.commands = commands
        self.eventCount = eventCount
        self.events = events
    }
    
    public var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
    
    public var primaryAppName: String {
        appNames.first ?? "Unknown App"
    }
    
    public var shortSummary: String {
        var parts: [String] = []
        parts.append(primaryAppName)
        
        if !commands.isEmpty {
            parts.append("\(commands.count) command\(commands.count == 1 ? "" : "s")")
        }
        
        let minutes = max(Int(duration / 60), 1)
        parts.append("\(minutes)m")
        return parts.joined(separator: " • ")
    }
}

public enum ActivityFormatting {
    public static let relativeDateTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    public static let sessionTime: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    public static let eventTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    
    public static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    public static let historyMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter
    }()

    public static func historySessionStamp(startedAt: Date, endedAt: Date) -> String {
        let day = Calendar.current.component(.day, from: startedAt)
        return "\(day)\(ordinalSuffix(for: day)) \(historyMonthYear.string(from: startedAt)) · \(shortTime.string(from: startedAt)) to \(shortTime.string(from: endedAt))"
    }

    public static func ordinalSuffix(for day: Int) -> String {
        let tens = day % 100
        if tens >= 11 && tens <= 13 {
            return "th"
        }

        switch day % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

import Foundation
import LogbookCore

enum LogbookCLI {
    static func run() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        
        guard let command = arguments.first else {
            printUsage()
            return
        }
        
        switch command {
        case "view":
            runView(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            printUsage()
        default:
            fputs("Unknown command: \(command)\n\n", stderr)
            printUsage()
            Foundation.exit(1)
        }
    }
    
    private static func runView(arguments: [String]) {
        let mode = parseMode(arguments: arguments)
        let limit = parseLimit(arguments: arguments) ?? 20
        let includeAllDates = arguments.contains("--all")
        let store = SessionStore()
        let events = store.recentEvents(limit: 5_000)
        let filteredEvents = includeAllDates ? events : events.filter { Calendar.current.isDateInToday($0.occurredAt) }
        
        switch mode {
        case .sessions:
            printSessions(store.sessionHistory(limit: limit), includeAllDates: includeAllDates)
        case .events:
            printEvents(filteredEvents, limit: limit, includeAllDates: includeAllDates)
        case .summary:
            printSummary(filteredEvents, includeAllDates: includeAllDates)
        }
    }
    
    private static func printSessions(_ sessions: [StoredSession], includeAllDates: Bool) {
        if sessions.isEmpty {
            print(includeAllDates ? "No captured sessions yet." : "No captured sessions for today yet.")
            return
        }
        
        print(includeAllDates ? "Logbook sessions" : "Today's sessions")
        print("")
        
        for session in sessions {
            let window = ActivityFormatting.sessionTime.string(from: session.startedAt, to: session.endedAt)
            print("\(window)  \(session.goal)")
            if let summary = session.summary {
                print("  \(summary)")
            }
            if !session.primaryLabels.isEmpty {
                print("  \(session.primaryLabels.joined(separator: " • "))")
            }
            print("")
        }
    }
    
    private static func printEvents(_ events: [ActivityEvent], limit: Int, includeAllDates: Bool) {
        let visibleEvents = Array(events.suffix(limit).reversed())
        
        if visibleEvents.isEmpty {
            print(includeAllDates ? "No captured events yet." : "No captured events for today yet.")
            return
        }
        
        print(includeAllDates ? "Logbook events" : "Today's events")
        print("")
        
        for event in visibleEvents {
            let timestamp = ActivityFormatting.eventTimestamp.string(from: event.occurredAt)
            let label = eventLabel(event)
            let detail = [
                event.appName,
                event.windowTitle,
                event.resourceTitle,
                event.domain,
                event.path,
                event.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent },
            ]
            .compactMap { $0 }
            .joined(separator: " • ")
            
            print("\(timestamp)  \(label)")
            if !detail.isEmpty {
                print("  \(detail)")
            }
            if let command = event.command {
                print("  $ \(command)")
            }
            print("")
        }
    }
    
    private static func printSummary(_ events: [ActivityEvent], includeAllDates: Bool) {
        let sessions = Sessionizer.sessions(from: events)
        let summaryDate = includeAllDates ? (events.last?.occurredAt ?? Date()) : Date()
        print(Sessionizer.dailySummary(for: sessions, date: summaryDate))
    }
    
    private static func parseMode(arguments: [String]) -> ViewMode {
        if arguments.contains("--events") {
            return .events
        }
        
        if arguments.contains("--summary") {
            return .summary
        }
        
        return .sessions
    }
    
    private static func parseLimit(arguments: [String]) -> Int? {
        guard let flagIndex = arguments.firstIndex(of: "--limit"), arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        
        return Int(arguments[flagIndex + 1])
    }
    
    private static func eventLabel(_ event: ActivityEvent) -> String {
        switch event.kind {
        case .appActivated:
            return "Activated \(event.appName ?? "Unknown App")"
        case .appLaunched:
            return "Launched \(event.appName ?? "Unknown App")"
        case .appTerminated:
            return "Terminated \(event.appName ?? "Unknown App")"
        case .systemWoke:
            return "System Woke"
        case .systemSlept:
            return "System Slept"
        case .windowChanged:
            return event.windowTitle ?? "Window Changed"
        case .fileCreated:
            return "File Created"
        case .fileModified:
            return "File Modified"
        case .fileRenamed:
            return "File Renamed"
        case .fileDeleted:
            return "File Deleted"
        case .commandStarted:
            return "Command Started"
        case .commandFinished:
            return "Command Finished"
        case .tabFocused:
            return "Tab Focused"
        case .tabChanged:
            return "Tab Changed"
        case .userIdle:
            return "User Idle"
        case .userResumed:
            return "User Resumed"
        case .clipboardChanged:
            return "Clipboard Changed"
        case .noteAdded:
            return "Note Added"
        case .sessionPinned:
            return "Session Pinned"
        case .capturePaused:
            return "Capture Paused"
        case .captureResumed:
            return "Capture Resumed"
        case .focusGuardPrompted:
            return "Focus Guard Prompted"
        case .focusGuardRecovered:
            return "Focus Guard Recovered"
        case .focusGuardSnoozed:
            return "Focus Guard Snoozed"
        case .focusGuardIgnored:
            return "Focus Guard Ignored"
        }
    }
    
    private static func printUsage() {
        print(
            """
            logbook
            
            Usage:
              logbook view [--events | --summary] [--limit N] [--all]
            
            Examples:
              swift run logbook view
              swift run logbook view --events --limit 10
              swift run logbook view --summary
              swift run logbook view --all
            """
        )
    }
    
    private enum ViewMode {
        case sessions
        case events
        case summary
    }
}

LogbookCLI.run()

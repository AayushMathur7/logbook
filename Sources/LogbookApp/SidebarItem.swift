import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case session
    case history
    case signals
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .session:
            return "Session"
        case .history:
            return "History"
        case .signals:
            return "Signals"
        case .settings:
            return "Settings"
        }
    }
}

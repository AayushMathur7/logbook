import Foundation

struct CalendarEventSummary: Identifiable, Hashable {
    let id: String
    let title: String
    let calendarTitle: String
    let startAt: Date
    let endAt: Date
    
    var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
}

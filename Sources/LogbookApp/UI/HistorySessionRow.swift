import LogbookCore
import SwiftUI

struct HistorySessionRow: View {
    let session: StoredSession
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(primaryLine)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)

            if primaryLine != session.goal {
                Text(session.goal)
                    .font(.system(size: 11))
                    .foregroundStyle(LogbookStyle.subtleText)
                    .lineLimit(1)
            }

            Text(sessionStamp)
                .font(.system(size: 10))
                .foregroundStyle(LogbookStyle.subtleText.opacity(0.88))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? LogbookStyle.badgeFill : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? LogbookStyle.badgeStroke : Color.clear, lineWidth: 1)
                )
        )
    }

    private var primaryLine: String {
        if let headline = session.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !headline.isEmpty {
            return headline
        }
        return session.goal
    }

    private var sessionStamp: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: session.startedAt)

        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM, yyyy"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        return "\(day)\(ordinalSuffix(for: day)) \(monthYearFormatter.string(from: session.startedAt)) · \(timeFormatter.string(from: session.startedAt)) to \(timeFormatter.string(from: session.endedAt))"
    }

    private func ordinalSuffix(for day: Int) -> String {
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

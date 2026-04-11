import LogbookCore
import SwiftUI

struct HistorySessionRow: View {
    let session: StoredSession
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(primaryLine)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)

            if primaryLine != session.goal {
                Text(session.goal)
                    .font(.system(size: 11))
                    .foregroundStyle(LogbookStyle.subtleText)
                    .lineLimit(1)
            }

            Text(ActivityFormatting.sessionTime.string(from: session.startedAt, to: session.endedAt))
                .font(.system(size: 10))
                .foregroundStyle(LogbookStyle.subtleText.opacity(0.88))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

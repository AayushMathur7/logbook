import DriftlyCore
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
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .lineLimit(1)
            }

            Text(sessionStamp)
                .font(.system(size: 10))
                .foregroundStyle(DriftlyStyle.subtleText.opacity(0.88))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? DriftlyStyle.badgeFill : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isSelected ? DriftlyStyle.badgeStroke : Color.clear, lineWidth: 1)
                )
        )
    }

    private var primaryLine: String {
        if let headline = session.headline?.trimmingCharacters(in: .whitespacesAndNewlines), !headline.isEmpty {
            return headline
        }

        switch session.reviewStatus {
        case .failed, .unavailable, .pending:
            return session.reviewStatus.historyTitle
        case .none, .ready:
            return session.goal
        }
    }

    private var sessionStamp: String {
        ActivityFormatting.historySessionStamp(startedAt: session.startedAt, endedAt: session.endedAt)
    }
}

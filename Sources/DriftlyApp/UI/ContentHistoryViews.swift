import Foundation
import DriftlyCore
import SwiftUI

extension ContentView {
    var previousSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library")
                .font(.system(size: 13, weight: .semibold))

            if model.historySessions.isEmpty, model.latestDailySummary == nil, model.latestWeeklySummary == nil {
                Text("No saved sessions yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DriftlyStyle.subtleText)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    FadingEdgeScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("History")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .padding(.bottom, 2)

                            if model.historySessions.isEmpty {
                                Text("No saved sessions yet.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                                    .padding(.top, 4)
                            } else {
                                ForEach(model.historySessions) { session in
                                    Button {
                                        model.selectHistorySession(session.id)
                                    } label: {
                                        HistorySessionRow(
                                            session: session,
                                            isSelected: model.selectedHistoryDetail?.session.id == session.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 224, alignment: .top)
                    .frame(maxHeight: 348, alignment: .top)

                    Divider()
                        .frame(maxHeight: 348)

                    Group {
                        if let summary = model.selectedPeriodicSummary() {
                            periodicSummaryDetail(summary)
                        } else if let detail = model.selectedHistoryDetail {
                            if let review = detail.review?.review {
                                reviewDetail(review: review, sessionID: detail.session.id, allowRetry: false, allowNextSession: false)
                            } else {
                                sessionTimelineOnly(detail: detail)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a session")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Pick a saved block on the left, or open a summary from the top bar.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .frame(width: 420, alignment: .topLeading)
                    .frame(maxHeight: 348, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    func periodicSummaryDetail(_ summary: StoredPeriodicSummary) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(summary.kind == .daily ? "Daily" : "Weekly")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DriftlyStyle.subtleText)

                    Spacer(minLength: 8)

                    Text("Ran \(summaryGeneratedStamp(summary))")
                        .font(.system(size: 11))
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.78))
                }

                Text(summaryPeriodStamp(summary))
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText.opacity(0.9))
            }

            Text(summary.title)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                Text(summary.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.nextStep)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DriftlyStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    func reviewDetail(review: SessionReview, sessionID: String?, allowRetry: Bool, allowNextSession: Bool) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.sessionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DriftlyStyle.subtleText)
                        .lineLimit(1)

                    Text(ActivityFormatting.historySessionStamp(startedAt: review.startedAt, endedAt: review.endedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.9))
                }
                Spacer()

                if allowNextSession {
                    HStack(spacing: 8) {
                        primaryReviewActionButton("Start another", systemImage: "arrow.right") {
                            model.startNextSession()
                        }

                        if allowRetry {
                            chromeActionButton("Retry", systemImage: "arrow.clockwise") {
                                model.retryLastReview()
                            }
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        if let selectedSessionID = model.selectedHistoryDetail?.session.id,
                           model.reviewInFlightSessionID == selectedSessionID {
                            historyLoadingPill("Retrying")
                        } else {
                            historyIconButton("Retry", systemImage: "arrow.clockwise") {
                                model.reviewSelectedHistorySessionAgain()
                            }
                        }

                        if let selectedSessionID = model.selectedHistoryDetail?.session.id {
                            historyIconButton("Delete", systemImage: "trash") {
                                model.deleteHistorySession(selectedSessionID)
                            }
                        }
                    }
                }
            }

            Text(review.headline)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                RichReviewText(
                    spans: review.summarySpans,
                    fallbackMarkdown: emphasizedReviewMarkdown(review.summary),
                    font: .system(size: 13),
                    color: DriftlyStyle.subtleText,
                    entityStyle: .inlineChip
                )

                if let insight = review.focusAssessment?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !insight.isEmpty {
                    MarkdownText(
                        emphasizedReviewMarkdown(insight),
                        font: .system(size: 13),
                        color: DriftlyStyle.subtleText,
                        useAttributedLayout: true
                    )
                }

                if let sessionID {
                    ReviewLearningBar(model: model, sessionID: sessionID, review: review)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    func emphasizedReviewMarkdown(_ value: String) -> String {
        var result = softWrapReviewText(value)

        result = result.replacingOccurrences(
            of: #"(?<![=\w])(\d{1,3}%)(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"(?<![\w])(\d+\s+of\s+\d+\s+minutes?)(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"(?<![\w])(\d+\s*(?:minutes?|minute|mins?|min|hours?|hour|hrs?|hr|seconds?|second|secs?|sec|s))(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"(?<![\w])(\d+\s+switches?)(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        return result
    }

    func softWrapReviewText(_ value: String) -> String {
        var result = value
        let zeroWidthSpace = "\u{200B}"

        result = result.replacingOccurrences(
            of: #"(@[A-Za-z0-9_]{10})([A-Za-z0-9_]+)"#,
            with: "$1\(zeroWidthSpace)$2",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"([A-Za-z0-9]{14})([A-Za-z0-9]{6,})"#,
            with: "$1\(zeroWidthSpace)$2",
            options: .regularExpression
        )

        return result
    }

    func reviewErrorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                Spacer()

                HStack(spacing: 8) {
                    primaryReviewActionButton("Start another", systemImage: "arrow.right") {
                        model.startNextSession()
                    }

                    chromeActionButton("Retry", systemImage: "arrow.clockwise") {
                        model.retryLastReview()
                    }
                }
            }

            Text("Review failed")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DriftlyStyle.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
    }

    func sessionTimelineOnly(detail: StoredSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.session.goal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DriftlyStyle.subtleText)

                    Text(ActivityFormatting.historySessionStamp(startedAt: detail.session.startedAt, endedAt: detail.session.endedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 4) {
                    if model.reviewInFlightSessionID == detail.session.id {
                        historyLoadingPill("Retrying")
                    } else {
                        historyIconButton("Retry", systemImage: "arrow.clockwise") {
                            model.reviewSelectedHistorySessionAgain()
                        }
                    }

                    historyIconButton("Delete", systemImage: "trash") {
                        model.deleteHistorySession(detail.session.id)
                    }
                }
            }
            if let statusMessage = historyStatusMessage(for: detail.session.reviewStatus) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(detail.session.reviewStatus.historyTitle)
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(DriftlyStyle.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(statusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(DriftlyStyle.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let summary = detail.session.summary {
                Text(summary)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(DriftlyStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(detail.session.goal)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(DriftlyStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    func historyStatusMessage(for status: ReviewStatus) -> String? {
        switch status {
        case .pending:
            return "This session finished, but the review has not been saved yet."
        case .unavailable:
            return "Driftly could not generate a review because the selected AI provider was not ready."
        case .failed:
            return "The selected AI provider did not return a usable review for this session. Retry it after checking your provider setup or output."
        case .none, .ready:
            return nil
        }
    }

    func chromeActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    func primaryReviewActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(DriftlyStyle.badgeFill)
                )
                .overlay(
                    Capsule()
                        .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    func historyIconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HistoryIconButton(title: title, systemImage: systemImage, action: action)
    }

    func historyLoadingPill(_ title: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.72)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(DriftlyStyle.subtleText)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }
}

private let summaryRowDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM yyyy"
    return formatter
}()

private func summaryPeriodStamp(_ summary: StoredPeriodicSummary) -> String {
    let periodStart = summaryRowDateFormatter.string(from: summary.periodStart)
    let periodEnd = summaryRowDateFormatter.string(from: summary.periodEnd)

    if periodStart == periodEnd {
        return periodStart
    }

    return "\(periodStart) to \(periodEnd)"
}

private let summaryGeneratedAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM yyyy, h:mm a"
    return formatter
}()

private func summaryGeneratedStamp(_ summary: StoredPeriodicSummary) -> String {
    summaryGeneratedAtFormatter.string(from: summary.generatedAt)
}

private struct HistoryIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? DriftlyStyle.text : DriftlyStyle.subtleText)
                .frame(width: 28, height: 28)
                .background(
                    Capsule()
                        .fill(isHovering ? DriftlyStyle.badgeFill : Color.clear)
                )
                .overlay(
                    Capsule()
                        .stroke(isHovering ? DriftlyStyle.cardStroke : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .onHover { isHovering = $0 }
    }
}

private struct ReviewLearningBar: View {
    @ObservedObject var model: AppModel
    let sessionID: String
    let review: SessionReview

    @State private var storedFeedback: SessionReviewFeedback?
    @State private var showCorrectionField = false
    @State private var correctionDraft = ""
    @State private var pendingHelpfulValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                LearningIconButton(
                    title: "Helpful",
                    systemImage: "hand.thumbsup",
                    isSelected: storedFeedback?.wasHelpful == true
                ) {
                    pendingHelpfulValue = true
                    correctionDraft = storedFeedback?.wasHelpful == true ? (storedFeedback?.note ?? correctionDraft) : ""
                    showCorrectionField = true
                }

                LearningIconButton(
                    title: "Needs work",
                    systemImage: "hand.thumbsdown",
                    isSelected: storedFeedback?.wasHelpful == false
                ) {
                    pendingHelpfulValue = false
                    showCorrectionField = true
                    correctionDraft = storedFeedback?.wasHelpful == false ? (storedFeedback?.note ?? correctionDraft) : ""
                }

                if storedFeedback != nil {
                    Text("Saved")
                        .font(.system(size: 11))
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.72))
                }
            }

            if showCorrectionField {
                HStack(spacing: 6) {
                    TextField(feedbackPlaceholder, text: $correctionDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DriftlyStyle.inputText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DriftlyStyle.inputFill)
                        )

                    Button {
                        let note = correctionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.saveReviewFeedback(sessionID: sessionID, review: review, wasHelpful: pendingHelpfulValue, note: note)
                        storedFeedback = model.reviewFeedback(for: sessionID)
                        showCorrectionField = false
                        correctionDraft = storedFeedback?.note ?? ""
                    } label: {
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DriftlyStyle.badgeFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(correctionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(correctionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
        }
        .onAppear {
            refresh()
        }
        .onChange(of: sessionID) { _ in
            refresh()
        }
    }

    private func refresh() {
        storedFeedback = model.reviewFeedback(for: sessionID)
        if let storedFeedback {
            pendingHelpfulValue = storedFeedback.wasHelpful
            correctionDraft = storedFeedback.note ?? ""
        } else {
            pendingHelpfulValue = false
            correctionDraft = ""
        }
        showCorrectionField = false
    }

    private var feedbackPlaceholder: String {
        pendingHelpfulValue ? "What was right about this review?" : "What did I miss or get wrong?"
    }
}

private struct LearningIconButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var isDisabled = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(title)
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        if isDisabled { return DriftlyStyle.subtleText.opacity(0.6) }
        if isSelected { return DriftlyStyle.text }
        return isHovering ? DriftlyStyle.text : DriftlyStyle.subtleText
    }

    private var backgroundColor: Color {
        if isSelected { return DriftlyStyle.badgeFill }
        return isHovering ? DriftlyStyle.badgeFill.opacity(0.82) : Color.clear
    }

    private var strokeColor: Color {
        if isSelected || isHovering { return DriftlyStyle.cardStroke }
        return Color.clear
    }
}

private struct ReviewEntityStrip: View {
    let entities: [SessionReviewEntity]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entities) { entity in
                    let badge = SourceBadgeFactory.badge(for: entity)
                    if let urlString = entity.url,
                       let url = URL(string: urlString) {
                        Link(destination: url) {
                            SourceBadge(badge: badge)
                        }
                        .buttonStyle(.plain)
                    } else {
                        SourceBadge(badge: badge)
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct FadingEdgeScrollView<Content: View>: View {
    let content: Content
    private let coordinateSpaceName = "history-list-scroll"
    private let fadeHeight: CGFloat = 34
    private let fadeThreshold: CGFloat = 4

    @State private var contentFrame: CGRect = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { viewportProxy in
            ScrollView {
                content
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: HistoryScrollContentFramePreferenceKey.self,
                                    value: proxy.frame(in: .named(coordinateSpaceName))
                                )
                        }
                    )
            }
            .coordinateSpace(name: coordinateSpaceName)
            .scrollIndicators(.hidden)
            .overlay(alignment: .top) {
                edgeFade(direction: .top, isVisible: showsTopFade)
            }
            .overlay(alignment: .bottom) {
                edgeFade(direction: .bottom, isVisible: showsBottomFade(viewportHeight: viewportProxy.size.height))
            }
            .onPreferenceChange(HistoryScrollContentFramePreferenceKey.self) { contentFrame = $0 }
        }
    }

    private var showsTopFade: Bool {
        contentFrame.minY < -fadeThreshold
    }

    private func showsBottomFade(viewportHeight: CGFloat) -> Bool {
        contentFrame.maxY > viewportHeight + fadeThreshold
    }

    @ViewBuilder
    private func edgeFade(direction: VerticalEdge, isVisible: Bool) -> some View {
        LinearGradient(
            colors: direction == .top
                ? [DriftlyStyle.canvasTop, DriftlyStyle.canvasTop.opacity(0.94), DriftlyStyle.canvasTop.opacity(0)]
                : [DriftlyStyle.canvasBottom.opacity(0), DriftlyStyle.canvasBottom.opacity(0.94), DriftlyStyle.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: fadeHeight)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }
}

private struct HistoryScrollContentFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

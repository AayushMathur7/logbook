import Foundation
import DriftlyCore
import SwiftUI

private enum ActiveSheet: Identifiable {
    case settings

    var id: Int {
        switch self {
        case .settings: return 0
        }
    }
}

private enum MainPane {
    case session
    case history
}

struct ContentView: View {
    private enum WindowMetrics {
        static let width: CGFloat = 728
        static let height: CGFloat = 500
    }

    @ObservedObject var model: AppModel
    @State private var activeSheet: ActiveSheet?
    @State private var activePane: MainPane = .session
    @State private var sessionGoalDraft = ""
    @State private var sessionPaneStateBeforeHistory: SessionScreenState?

    var body: some View {
        ZStack {
            background

            ScrollView {
                mainColumn
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: WindowMetrics.width, height: WindowMetrics.height)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsSheet(model: model)
            }
        }
        .textSelection(.enabled)
        .animation(.easeInOut(duration: 0.22), value: model.surfaceState)
        .onAppear {
            syncSessionGoalDraftFromModel()
        }
        .onChange(of: model.surfaceState) { _ in
            syncSessionGoalDraftFromModel()
        }
        .onChange(of: model.settingsSheetRequestID) { requestID in
            guard requestID > 0 else { return }
            activeSheet = .settings
        }
    }

    private var mainColumn: some View {
        VStack(alignment: .center, spacing: 12) {
            topBar
            primaryContent
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var background: some View {
        LinearGradient(
            colors: [DriftlyStyle.canvasTop, DriftlyStyle.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                guard activePane == .history else { return }
                activePane = .session
                model.clearHistorySelection()
                model.restorePrimarySessionSurface(preferred: sessionPaneStateBeforeHistory)
                sessionPaneStateBeforeHistory = nil
            } label: {
                HStack(spacing: 6) {
                    DriftlyMarkView()
                        .frame(width: 34, height: 10)
                    DriftlyWordmarkView()
                }
            }
            .buttonStyle(.plain)
            .help("Session")

            Spacer(minLength: 0)

            Button {
                if activePane == .history {
                    activePane = .session
                    model.clearHistorySelection()
                    model.restorePrimarySessionSurface(preferred: sessionPaneStateBeforeHistory)
                    sessionPaneStateBeforeHistory = nil
                } else {
                    sessionPaneStateBeforeHistory = model.surfaceState
                    activePane = .history
                    model.ensureHistorySelection()
                }
            } label: {
                Image(systemName: activePane == .history ? "rectangle.on.rectangle" : "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        Capsule()
                            .fill(activePane == .history ? AnyShapeStyle(DriftlyStyle.badgeFill) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .overlay(
                        Capsule()
                            .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.historySessions.isEmpty)
            .help(activePane == .history ? "Session" : "History")

            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if activePane == .history {
            historyPrimaryContent
        } else {
            switch model.surfaceState {
            case .setup:
                centeredPrimaryContent(setupView)
            case .running:
                if let activeSession = model.activeSession {
                    centeredPrimaryContent(runningView(session: activeSession))
                } else {
                    centeredPrimaryContent(setupView)
                }
            case .generatingReview:
                centeredPrimaryContent(generatingView)
            case .reviewReady:
                if let review = model.lastSessionReview {
                    centeredPrimaryContent(reviewDetail(review: review, sessionID: model.latestSessionID, allowRetry: true, allowNextSession: true))
                } else if let reviewError = model.lastReviewErrorMessage, !reviewError.isEmpty {
                    centeredPrimaryContent(reviewErrorView(message: reviewError))
                } else {
                    centeredPrimaryContent(setupView)
                }
            }
        }
    }

    private var historyPrimaryContent: some View {
        VStack {
            Spacer(minLength: 14)
            previousSessionsSection
                .frame(maxWidth: 672, alignment: .leading)
            Spacer(minLength: 14)
        }
        .frame(minHeight: WindowMetrics.height - 92)
    }

    private func centeredPrimaryContent<Content: View>(_ content: Content) -> some View {
        VStack {
            Spacer(minLength: 18)
            content
                .frame(maxWidth: 540, alignment: .leading)
            Spacer(minLength: 18)
        }
        .frame(minHeight: WindowMetrics.height - 92)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What are you focusing on?")
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(DriftlyStyle.text)
                        .padding(.bottom, 10)
                    TextField(
                        "Write the page, finish the deck, clear your inbox, ship the fix…",
                        text: $sessionGoalDraft
                    )
                    .textFieldStyle(.plain)
                    .font(DriftlyStyle.uiFont(size: 13, weight: .regular))
                    .foregroundStyle(DriftlyStyle.inputText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DriftlyStyle.inputFill)
                    )
                    .onSubmit {
                        if sessionGoalIsValid {
                            startSessionFromDraft()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DriftlyStyle.subtleText)
                        Spacer()
                        Text("\(model.sessionDurationMinutes) min")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(model.sessionDurationMinutes) },
                            set: { model.setSessionDuration(Int($0.rounded())) }
                        ),
                        in: 5...120,
                        step: 5
                    )
                    .tint(DriftlyStyle.accent)

                    HStack {
                        Text("5m")
                        Spacer()
                        Text("45m")
                        Spacer()
                        Text("120m")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                }

                if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                    InlineMessage(text: errorMessage, tint: DriftlyStyle.warning)
                }

                if !model.localReviewConfigured {
                    InlineMessage(text: model.localReviewSetupSummary, tint: DriftlyStyle.caution)
                }

                if let accessibilitySummary = model.accessibilitySetupSummary {
                    InlineActionMessage(
                        text: accessibilitySummary,
                        actionTitle: "Turn on Accessibility",
                        actionURL: AccessibilityInspector.settingsURLs[0],
                        tint: DriftlyStyle.caution
                    )
                }

                Button {
                    startSessionFromDraft()
                } label: {
                    Text("Start session")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!sessionGoalIsValid)

                if !model.localReviewConfigured {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("Set up local review", systemImage: "gearshape.fill")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func runningView(session: FocusSession) -> some View {
        VStack(alignment: .center, spacing: 22) {
            Text(session.title)
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(alignment: .center, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remainingLabel(session: session, now: context.date))
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity)

            openAIActionButton("End session", systemImage: "stop.fill") {
                model.endSessionNow()
            }
        }
        .frame(maxWidth: 540)
        .padding(.horizontal, 12)
    }

    private var generatingView: some View {
        VStack(alignment: .center, spacing: 14) {
            Spacer(minLength: 0)

            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.15)

            Text("Generating review")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)

            Text(model.evidenceStatusText)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.subtleText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, 12)
    }

    private var previousSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))

            if model.historySessions.isEmpty {
                Text("No saved sessions yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(DriftlyStyle.subtleText)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    FadingEdgeScrollView {
                        VStack(alignment: .leading, spacing: 8) {
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
                    .frame(width: 224, alignment: .top)
                    .frame(maxHeight: 348, alignment: .top)

                    Divider()
                        .frame(maxHeight: 348)

                    Group {
                        if let detail = model.selectedHistoryDetail {
                            if let review = detail.review?.review {
                                reviewDetail(review: review, sessionID: detail.session.id, allowRetry: false, allowNextSession: false)
                            } else {
                                sessionTimelineOnly(detail: detail)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a session")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Pick a saved block to review what happened.")
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

    private func reviewDetail(review: SessionReview, sessionID: String?, allowRetry: Bool, allowNextSession: Bool) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(review.sessionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DriftlyStyle.subtleText)
                        .lineLimit(1)

                    Text(historySessionStamp(startedAt: review.startedAt, endedAt: review.endedAt))
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
                        if let sessionID = model.selectedHistoryDetail?.session.id,
                           model.reviewInFlightSessionID == sessionID {
                            historyLoadingPill("Retrying")
                        } else {
                            historyIconButton("Retry", systemImage: "arrow.clockwise") {
                                model.reviewSelectedHistorySessionAgain()
                            }
                        }

                        if let sessionID = model.selectedHistoryDetail?.session.id {
                            historyIconButton("Delete", systemImage: "trash") {
                                model.deleteHistorySession(sessionID)
                            }
                        }
                    }
                }
            }

            Text(review.headline)
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                MarkdownText(
                    emphasizedReviewMarkdown(review.summary),
                    font: .system(size: 13),
                    color: DriftlyStyle.subtleText,
                    useAttributedLayout: true
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

    private func emphasizedReviewMarkdown(_ value: String) -> String {
        var result = softWrapReviewText(value)

        result = result.replacingOccurrences(
            of: #"(?<![=\w])(\d{1,3}%)(?!\w)"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"(?<![\w])(\d+\s*(?:minutes?|minute|mins?|min|seconds?|second|secs?|sec|s))(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"(?<![\w])(\d+\s+of\s+\d+\s+minutes?)(?![\w])"#,
            with: "==$1==",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #""([^"\n]{4,80})""#,
            with: "\"*$1*\"",
            options: .regularExpression
        )

        let labels = ReviewEntityRegistry.promptEntities()
            .map(\.label)
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                return lhs.count > rhs.count
            }

        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern: String
            if label.lowercased() == "x" {
                pattern = #"(?<![=\w])\#(escaped)(?![=\w])"#
            } else {
                pattern = #"(?<!==)(?<![\w])\#(escaped)(?![\w])(?!==)"#
            }

            result = result.replacingOccurrences(
                of: pattern,
                with: "==\(label)==",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private func softWrapReviewText(_ value: String) -> String {
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

    private func reviewErrorView(message: String) -> some View {
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

    private func sessionTimelineOnly(detail: StoredSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.session.goal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DriftlyStyle.subtleText)

                    Text(historySessionStamp(startedAt: detail.session.startedAt, endedAt: detail.session.endedAt))
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
                    Text(historyStatusTitle(for: detail.session.reviewStatus))
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

    private func historyStatusTitle(for status: ReviewStatus) -> String {
        switch status {
        case .pending:
            return "Review pending"
        case .unavailable:
            return "Review unavailable"
        case .failed:
            return "Review failed"
        case .none, .ready:
            return ""
        }
    }

    private func historyStatusMessage(for status: ReviewStatus) -> String? {
        switch status {
        case .pending:
            return "This session finished, but the review has not been saved yet."
        case .unavailable:
            return "No local model was available for this session, so Driftly could not generate a review."
        case .failed:
            return "The model did not return a usable review for this session. Retry it after checking your Ollama setup or model output."
        case .none, .ready:
            return nil
        }
    }

    private func historySessionStamp(startedAt: Date, endedAt: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: startedAt)

        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM, yyyy"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        return "\(day)\(ordinalSuffix(for: day)) \(monthYearFormatter.string(from: startedAt)) · \(timeFormatter.string(from: startedAt)) to \(timeFormatter.string(from: endedAt))"
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

    private func chromeActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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

    private func primaryReviewActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
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

    private func historyIconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        HistoryIconButton(title: title, systemImage: systemImage, action: action)
    }

    private func historyLoadingPill(_ title: String) -> some View {
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

    private func openAIActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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

    private func syncSessionGoalDraftFromModel() {
        guard model.surfaceState == .setup else { return }
        if sessionGoalDraft.isEmpty {
            sessionGoalDraft = model.sessionDraftTitle
        }
    }

    private var sessionGoalIsValid: Bool {
        !sessionGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startSessionFromDraft() {
        model.sessionDraftTitle = sessionGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.startSession()
    }

    private func remainingLabel(session: FocusSession, now: Date) -> String {
        let remaining = max(Int(session.endsAt.timeIntervalSince(now)), 0)
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            content()
        }
    }
    private func timelinePhases(from segments: [TimelineSegment]) -> [TimelinePhase] {
        guard !segments.isEmpty else { return [] }

        let context = timelineContext(from: segments)
        var groups: [[TimelineSegment]] = []
        var current: [TimelineSegment] = []
        var currentKey: String?

        for segment in segments {
            let style = timelinePhaseStyle(for: segment)
            let groupKey = timelinePhaseGroupKey(for: segment, style: style, context: context)
            if current.isEmpty {
                current = [segment]
                currentKey = groupKey
                continue
            }

            if groupKey == currentKey {
                current.append(segment)
            } else {
                groups.append(current)
                current = [segment]
                currentKey = groupKey
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }

        return groups.map { group in
            let style = timelinePhaseStyle(for: group[0])
            return TimelinePhase(
                segments: group,
                style: style,
                label: timelinePhaseLabel(for: group, style: style, context: context),
                metadata: timelinePhaseMetadata(for: group, style: style),
                overlays: [],
                sourceBadges: SourceBadgeFactory.badges(for: group),
                confidence: aggregateConfidence(for: group)
            )
        }
    }

    private func timelinePhases(from attentionSegments: [AttentionSegment]) -> [TimelinePhase] {
        guard !attentionSegments.isEmpty else { return [] }

        let foregrounds = attentionSegments.map(\.foreground)
        let context = timelineContext(from: foregrounds)
        var groups: [[AttentionSegment]] = []
        var current: [AttentionSegment] = []
        var currentKey: String?

        for attention in attentionSegments {
            let style = timelinePhaseStyle(for: attention.foreground)
            let groupKey = timelinePhaseGroupKey(for: attention.foreground, style: style, context: context)
            if current.isEmpty {
                current = [attention]
                currentKey = groupKey
                continue
            }

            if groupKey == currentKey {
                current.append(attention)
            } else {
                groups.append(current)
                current = [attention]
                currentKey = groupKey
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }

        return groups.map { group in
            let segments = group.map(\.foreground)
            let style = timelinePhaseStyle(for: segments[0])
            let overlays = group.flatMap(\.overlays)
            return TimelinePhase(
                segments: segments,
                style: style,
                label: timelinePhaseLabel(for: segments, style: style, context: context),
                metadata: timelinePhaseMetadata(for: segments, style: style),
                overlays: overlays,
                sourceBadges: SourceBadgeFactory.badges(for: segments),
                confidence: aggregateConfidence(for: group)
            )
        }
    }

    private func aggregateConfidence(for segments: [TimelineSegment]) -> AttentionConfidence {
        if segments.contains(where: { $0.confidence < 0.6 }) {
            return .low
        }
        if segments.contains(where: { $0.confidence < 0.85 }) {
            return .medium
        }
        return .high
    }

    private func aggregateConfidence(for attentionSegments: [AttentionSegment]) -> AttentionConfidence {
        if attentionSegments.contains(where: { $0.confidence == .low }) {
            return .low
        }
        if attentionSegments.contains(where: { $0.confidence == .medium }) {
            return .medium
        }
        return .high
    }

    private func timelinePhaseGroupKey(for segment: TimelineSegment, style: TimelinePhaseStyle, context: TimelineContext?) -> String {
        let app = segment.appName.lowercased()
        let primary = segment.primaryLabel.lowercased()
        let secondary = (segment.secondaryLabel ?? "").lowercased()
        let domain = (segment.domain ?? "").lowercased()
        let repo = (segment.repoName ?? "").lowercased()
        let file = segment.filePath.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? ""
        let contextToken = (context?.file ?? context?.repo ?? "").lowercased()

        switch style {
        case .focus:
            if domain == "github.com" {
                return "focus:github:\(secondary.isEmpty ? primary : secondary)"
            }
            if !file.isEmpty {
                return "focus:file:\(repo):\(file)"
            }
            if !repo.isEmpty {
                return "focus:repo:\(repo)"
            }
            if app == "codex" || app == "cursor" {
                return "focus:editor:\(app):\(contextToken)"
            }
            return "focus:\(app):\(secondary.isEmpty ? primary : secondary)"
        case .support:
            return "support:\(domain.isEmpty ? app : domain):\(secondary.isEmpty ? primary : secondary)"
        case .drift:
            return "drift:\(domain.isEmpty ? app : domain):\(secondary.isEmpty ? primary : secondary)"
        case .breakState:
            return "pause:\(primary)"
        case .neutral:
            return "neutral:\(app):\(secondary.isEmpty ? primary : secondary)"
        }
    }

    private func timelinePhaseStyle(for segment: TimelineSegment) -> TimelinePhaseStyle {
        let primary = segment.primaryLabel.lowercased()
        let secondary = segment.secondaryLabel?.lowercased() ?? ""
        let domain = (segment.domain ?? "").lowercased()
        let app = segment.appName.lowercased()

        if segment.appName == "Driftly" && primary.contains("break") {
            return .breakState
        }
        if primary.contains("new tab") || secondary.contains("new tab") {
            return .drift
        }
        if domain == "youtube.com" || domain == "youtu.be" || domain == "x.com" || domain == "twitter.com" {
            return .drift
        }
        if app.contains("spotify") || app.contains("music") {
            return .drift
        }
        if domain.contains("calendar.notion.so") || primary.contains("calendar") || secondary.contains("calendar") {
            return .drift
        }
        if segment.category == .coding || segment.category == .docs || segment.filePath != nil || segment.repoName != nil || domain == "github.com" {
            return .focus
        }
        if segment.category == .research {
            return .support
        }
        if segment.category == .admin {
            return .breakState
        }
        return .neutral
    }

    private func timelinePhaseLabel(for group: [TimelineSegment], style: TimelinePhaseStyle, context: TimelineContext?) -> String {
        let first = group.first
        switch style {
        case .focus:
            if let github = group.first(where: { ($0.domain ?? "") == "github.com" }), let secondary = github.secondaryLabel, secondary.contains("/") {
                return "Reviewing `\(secondary)` on GitHub"
            }
            if let file = group.compactMap({ $0.filePath }).map({ URL(fileURLWithPath: $0).lastPathComponent }).first(where: { !$0.isEmpty }),
               let repo = group.compactMap(\.repoName).first {
                return "Editing `\(file)` in `\(repo)`"
            }
            if let file = group.compactMap({ $0.filePath }).map({ URL(fileURLWithPath: $0).lastPathComponent }).first(where: { !$0.isEmpty }) {
                return "Editing `\(file)`"
            }
            if let app = first?.appName, (app == "Codex" || app == "Cursor"), let file = context?.file {
                if let repo = context?.repo {
                    return "Editing `\(file)` in `\(repo)`"
                }
                return "Editing `\(file)`"
            }
            if let app = first?.appName, (app == "Codex" || app == "Cursor"), let repo = context?.repo {
                return "Working in `\(repo)`"
            }
            if let repo = group.compactMap(\.repoName).first {
                return "Working in `\(repo)`"
            }
            if let app = first?.appName {
                return "Working in `\(app)`"
            }
            return "Working"
        case .support:
            if let github = group.first(where: { ($0.domain ?? "") == "github.com" }), let secondary = github.secondaryLabel {
                return "Checking `\(secondary)` on GitHub"
            }
            if group.contains(where: { ($0.domain ?? "").contains("calendar.notion.so") || $0.primaryLabel.lowercased().contains("calendar") }) {
                return "Checking `Notion Calendar`"
            }
            if let primary = group.map(\.primaryLabel).first(where: { !$0.lowercased().contains("new tab") }) {
                return "Checking `\(primary)`"
            }
            return "Support work"
        case .drift:
            if let spotify = group.first(where: { $0.appName.lowercased().contains("spotify") }) {
                if spotify.primaryLabel.lowercased() != "spotify" {
                    return "Spotify with `\(spotify.primaryLabel)` visible"
                }
                return "On `Spotify`"
            }
            if let youtube = group.first(where: { ($0.domain ?? "") == "youtube.com" || ($0.domain ?? "") == "youtu.be" }) {
                if youtube.primaryLabel == "YouTube Home" {
                    return "Drifted into `YouTube Home`"
                }
                if youtube.primaryLabel == "YouTube Shorts", let secondary = youtube.secondaryLabel, !secondary.isEmpty {
                    return "Viewed `\(secondary)` in YouTube Shorts"
                }
                if let secondary = youtube.secondaryLabel, !secondary.isEmpty {
                    return "Viewed `\(secondary)` on YouTube"
                }
                return "Drifted into `YouTube`"
            }
            if let xSegment = group.first(where: { ($0.domain ?? "") == "x.com" || ($0.domain ?? "") == "twitter.com" }) {
                if xSegment.secondaryLabel == "Home feed" {
                    return "Drifted into `X` home feed"
                }
                if let secondary = xSegment.secondaryLabel, !secondary.isEmpty {
                    return "Opened `\(secondary)` on `X`"
                }
                return "Drifted into `X`"
            }
            if group.contains(where: { ($0.domain ?? "").contains("calendar.notion.so") || $0.primaryLabel.lowercased().contains("calendar") }) {
                return "Checking `Notion Calendar`"
            }
            if group.contains(where: { $0.primaryLabel.lowercased().contains("new tab") }) {
                return "Sat in `New tab`"
            }
            return "Drift"
        case .breakState:
            if let note = group.first(where: { $0.appName == "Driftly" })?.primaryLabel.lowercased(), note.contains("1 min") || note.contains("1-minute") || note.contains("1 minute") {
                return "Took a 1-minute break"
            }
            if group.first(where: { $0.appName == "Driftly" })?.primaryLabel != nil {
                return "Took a break"
            }
            return "Pause"
        case .neutral:
            if let app = first?.appName {
                return "Used `\(app)`"
            }
            return group.first?.primaryLabel ?? "Mixed activity"
        }
    }

    private func timelinePhaseMetadata(for group: [TimelineSegment], style: TimelinePhaseStyle) -> String {
        let apps = group.map(\.appName).reduce(into: [String]()) { result, value in
            guard !result.contains(value) else { return }
            result.append(value)
        }
        let files = group
            .compactMap(\.filePath)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .reduce(into: [String]()) { result, value in
                guard !value.isEmpty, !result.contains(value) else { return }
                result.append(value)
            }
        let repos = group.compactMap(\.repoName).reduce(into: [String]()) { result, value in
            guard !result.contains(value) else { return }
            result.append(value)
        }
        let domains = group.compactMap(\.domain).reduce(into: [String]()) { result, value in
            guard !result.contains(value) else { return }
            result.append(value)
        }

        var parts: [String] = []
        if let app = apps.first {
            parts.append(app)
        }
        if let repo = repos.first {
            parts.append("repo \(repo)")
        }
        if let file = files.first {
            parts.append("file \(file)")
        } else if let domain = domains.first {
            parts.append(domain)
        }
        if group.reduce(0, { $0 + $1.eventCount }) > 1 {
            parts.append("\(group.reduce(0, { $0 + $1.eventCount })) events")
        }
        if style == .breakState, let note = group.first(where: { $0.appName == "Driftly" })?.primaryLabel {
            parts.append("note: \(note)")
        }

        return parts.joined(separator: " • ")
    }

    private func timelineContext(from segments: [TimelineSegment]) -> TimelineContext? {
        let file = segments
            .compactMap(\.filePath)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .first(where: { !$0.isEmpty })
        let repo = segments
            .compactMap(\.repoName)
            .first(where: { !$0.isEmpty })
        guard file != nil || repo != nil else { return nil }
        return TimelineContext(file: file, repo: repo)
    }
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

private struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DriftlyStyle.canvasBottom
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Settings")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    settingsChromeButton("Done") {
                        model.saveCaptureSettings()
                        dismiss()
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        settingsSection("Local model") {
                            Text("A local model is optional at first. If no model is ready, Driftly still saves the session, but AI review generation will not run.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model")
                                    .font(.system(size: 12, weight: .medium))
                                if model.availableOllamaModels.isEmpty {
                                    settingsTextField(title: "Model name (optional)", text: $model.ollamaModelName)
                                } else {
                                    Menu {
                                        ForEach(model.availableOllamaModels) { detectedModel in
                                            Button(detectedModel.name) {
                                                model.ollamaModelName = detectedModel.name
                                            }
                                        }
                                    } label: {
                                        settingsMenuField(model.ollamaModelName)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            HStack(spacing: 8) {
                                settingsTextField(title: "Base URL", text: $model.ollamaBaseURLInput)
                                settingsTextField(title: "Timeout", text: $model.ollamaTimeoutInput)
                                    .frame(width: 92)
                            }

                            HStack(spacing: 8) {
                                settingsChromeButton("Refresh") {
                                    Task { await model.refreshAvailableModels() }
                                }

                                settingsInlineToggle("Debug model I/O", isOn: $model.ollamaStoreDebugIO)
                            }

                            if !model.ollamaStatusMessage.isEmpty {
                                settingsStatusMessage(
                                    text: model.ollamaStatusMessage,
                                    isError: model.ollamaStatusIsError
                                )
                            }
                        }

                        settingsSection("Capture") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Nudges")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Send a quiet notification when Driftly sees clear drift during a session.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)

                                captureToggleRow(
                                    title: "Enable nudges",
                                    detail: "Uses the default cadence: waits a bit at the start, stays quiet unless drift looks clear, and sends only occasional recovery nudges.",
                                    isOn: Binding(
                                        get: { model.focusGuardEnabled },
                                        set: { model.setNudgesEnabled($0) }
                                    )
                                )

                                Text("Nudges use only local session signals and stay conservative when the evidence is mixed.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DriftlyStyle.subtleText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            captureToggleRow(
                                title: "Window titles",
                                detail: "Capture editor titles, browser page titles, and active document names when macOS allows it.",
                                isOn: $model.trackAccessibilityTitles
                            )
                            captureToggleRow(
                                title: "Browser context",
                                detail: "Capture page titles, domains, and URLs from supported browsers.",
                                isOn: $model.trackBrowserContext
                            )
                            captureToggleRow(
                                title: "Finder context",
                                detail: "Capture the current Finder folder when Finder is frontmost.",
                                isOn: $model.trackFinderContext
                            )
                            captureToggleRow(
                                title: "Shell commands",
                                detail: "Import terminal commands through the shell integration.",
                                isOn: $model.trackShellCommands
                            )
                            captureToggleRow(
                                title: "File activity",
                                detail: "Capture file changes under the watched paths that Driftly observes.",
                                isOn: $model.trackFileSystemActivity
                            )
                            captureToggleRow(
                                title: "Clipboard",
                                detail: "Capture short clipboard previews when the clipboard changes.",
                                isOn: $model.trackClipboard
                            )
                            captureToggleRow(
                                title: "Presence",
                                detail: "Capture idle, resume, wake, and sleep signals to explain pauses in the block.",
                                isOn: $model.trackPresence
                            )

                            HStack(spacing: 8) {
                                Text("Retention")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                settingsTextField(title: "Days", text: $model.rawEventRetentionDaysInput)
                                    .frame(width: 80)
                            }

                            Text("Nudges use only local session signals and keep the cadence internal so the product stays simple.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        settingsSection("Permissions") {
                            permissionRow(
                                title: "Accessibility",
                                subtitle: model.accessibilityTrusted
                                    ? "Enabled"
                                    : "Needed for window titles, browser page titles, and richer session context.",
                                actionTitle: model.accessibilityTrusted ? "Open pane" : "Open System Settings"
                            ) {
                                model.requestAccessibilityAccess()
                            }
                        }

                        settingsSection("Privacy") {
                            Text("Driftly stays local. It captures app, title, browser, shell, file, clipboard preview, and presence signals only when those sources are enabled. It does not capture screenshots, OCR, audio, camera, microphone, or keystrokes.")
                                .font(.system(size: 11))
                                .foregroundStyle(DriftlyStyle.subtleText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 8) {
                            settingsChromeButton("Save") {
                                model.saveCaptureSettings()
                                dismiss()
                            }

                            settingsChromeButton("Clear events") {
                                model.clearAllEvents()
                            }

                            settingsChromeButton("Clear debug") {
                                model.clearModelDebugData()
                            }
                        }

                        if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                            InlineMessage(text: errorMessage, tint: DriftlyStyle.warning)
                        }
                    }
                    .padding(.bottom, 12)
                    .textSelection(.enabled)
                }
            }
            .padding(16)
        }
        .frame(width: 480, height: 420)
        .background(DriftlyStyle.canvasBottom)
        .preferredColorScheme(.dark)
        .task {
            await model.refreshAvailableModels()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DriftlyStyle.subtleText)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            Divider()
                .overlay(DriftlyStyle.cardStroke.opacity(0.75))
                .padding(.top, 2)
        }
    }

    private func permissionRow(title: String, subtitle: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            settingsChromeButton(actionTitle, action: action)
        }
    }

    private func settingsTextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DriftlyStyle.inputFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
                )
        }
    }

    private func captureToggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            settingsSwitch(isOn: isOn)
        }
    }

    private func settingsStatusMessage(text: String, isError: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isError ? DriftlyStyle.warning : DriftlyStyle.subtleText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsMenuField(_ value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(DriftlyStyle.text)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DriftlyStyle.subtleText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DriftlyStyle.inputFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
        )
    }

    private func settingsChromeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(DriftlyStyle.badgeFill)
            )
            .overlay(
                Capsule()
                    .stroke(DriftlyStyle.cardStroke, lineWidth: 1)
            )
            .buttonStyle(.plain)
    }

    private func settingsInlineToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                settingsSwitch(isOn: isOn)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(DriftlyStyle.subtleText)
            }
        }
        .buttonStyle(.plain)
    }

    private func settingsSwitch(isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? DriftlyStyle.badgeFill : DriftlyStyle.inputFill)
                    .frame(width: 34, height: 20)
                    .overlay(
                        Capsule()
                            .stroke(isOn.wrappedValue ? DriftlyStyle.badgeStroke : DriftlyStyle.cardStroke, lineWidth: 1)
                    )
                Circle()
                    .fill(DriftlyStyle.text)
                    .frame(width: 14, height: 14)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

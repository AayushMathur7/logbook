import Foundation
import LogbookCore
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
    @State private var goalFieldFocused = false
    @State private var showLiveActivity = false

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
        .animation(.easeInOut(duration: 0.22), value: model.surfaceState)
        .onAppear {
            syncSessionGoalDraftFromModel()
        }
        .onChange(of: model.surfaceState) { _ in
            syncSessionGoalDraftFromModel()
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
            colors: [LogbookStyle.canvasTop, LogbookStyle.canvasBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Button {
                if activePane == .history {
                    activePane = .session
                    model.restorePrimarySessionSurface()
                } else {
                    activePane = .history
                    model.ensureHistorySelection()
                }
            } label: {
                Label(activePane == .history ? "Session" : "History", systemImage: activePane == .history ? "rectangle.on.rectangle" : "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(activePane == .history ? AnyShapeStyle(LogbookStyle.badgeFill) : AnyShapeStyle(.ultraThinMaterial))
                    )
                    .overlay(
                        Capsule()
                            .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.historySessions.isEmpty)

            Button {
                activeSheet = .settings
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
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
                    centeredPrimaryContent(reviewDetail(review: review, allowRetry: true, allowNextSession: true))
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
                    Text("Goal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LogbookStyle.subtleText)
                    ComposerTextField(
                        text: $sessionGoalDraft,
                        isFocused: Binding(
                            get: { goalFieldFocused },
                            set: { goalFieldFocused = $0 }
                        ),
                        placeholder: "Write homepage copy, debug auth, review the PR, ship the settings migration…"
                    ) {
                        if sessionGoalIsValid {
                            startSessionFromDraft()
                        }
                    }
                    .composerInputField(isFocused: goalFieldFocused)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Duration")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LogbookStyle.subtleText)
                        Spacer()
                        Text("\(model.sessionDurationMinutes) min")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(model.sessionDurationMinutes) },
                            set: { model.setSessionDuration(Int($0.rounded())) }
                        ),
                        in: 10...120,
                        step: 5
                    )
                    .tint(LogbookStyle.accent)

                    HStack {
                        Text("10m")
                        Spacer()
                        Text("45m")
                        Spacer()
                        Text("120m")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(LogbookStyle.subtleText)
                }

                if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                    InlineMessage(text: errorMessage, tint: LogbookStyle.warning)
                } else if model.permissionOnboardingItems.contains(where: { !$0.isSatisfied }) {
                    InlineMessage(
                        text: "Some permissions are still missing. Log Book will still work, but capture will be less detailed. Configure them in Settings.",
                        tint: LogbookStyle.caution
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
            }
        }
        .padding(.horizontal, 12)
    }

    private func runningView(session: FocusSession) -> some View {
        VStack(alignment: .center, spacing: 18) {
            Text(session.title)
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(alignment: .center, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(remainingLabel(session: session, now: context.date))
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
                Text(ActivityFormatting.sessionTime.string(from: session.startedAt, to: session.endsAt))
                    .font(.system(size: 12))
                    .foregroundStyle(LogbookStyle.subtleText)
            }
            .frame(maxWidth: .infinity)

            openAIActionButton("End session", systemImage: "stop.fill") {
                model.endSessionNow()
            }

            liveActivityPanel(session: session)
        }
        .frame(maxWidth: 540)
        .padding(.horizontal, 12)
    }

    private var generatingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generating review")
                .font(.system(size: 18, weight: .semibold))
            ProgressView()
                .controlSize(.large)
            Text(model.evidenceStatusText)
                .font(.system(size: 12))
                .foregroundStyle(LogbookStyle.subtleText)
        }
        .padding(.horizontal, 12)
    }

    private var previousSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))

            if model.historySessions.isEmpty {
                Text("No saved sessions yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(LogbookStyle.subtleText)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
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
                                reviewDetail(review: review, allowRetry: false, allowNextSession: false)
                            } else {
                                sessionTimelineOnly(detail: detail)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select a session")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Pick a saved block to review what happened.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LogbookStyle.subtleText)
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

    private func reviewDetail(review: SessionReview, allowRetry: Bool, allowNextSession: Bool) -> some View {
        VStack(alignment: .leading, spacing: allowNextSession ? 14 : 18) {
            HStack(alignment: .center) {
                if allowNextSession {
                    Text("Session review")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LogbookStyle.subtleText)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(review.sessionTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LogbookStyle.subtleText)
                            .lineLimit(1)

                        Text(historySessionStamp(startedAt: review.startedAt, endedAt: review.endedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(LogbookStyle.subtleText.opacity(0.9))
                    }
                }
                Spacer()
                if !allowNextSession {
                    HStack(spacing: 8) {
                        chromeActionButton("Retry", systemImage: "arrow.clockwise") {
                            model.reviewSelectedHistorySessionAgain()
                        }

                        if let sessionID = model.selectedHistoryDetail?.session.id {
                            chromeActionButton("Delete", systemImage: "trash") {
                                model.deleteHistorySession(sessionID)
                            }
                        }
                    }
                }
            }

            Text(review.headline)
                .font(
                    allowNextSession
                        ? .system(size: 22, weight: .semibold)
                        : .system(size: 24, weight: .semibold, design: .serif)
                )
                .fixedSize(horizontal: false, vertical: true)

            RichReviewText(
                spans: review.summarySpans,
                fallbackMarkdown: review.summary,
                font: .system(size: 13),
                color: LogbookStyle.subtleText
            )

            HStack(spacing: 10) {
                Text(review.sessionTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LogbookStyle.subtleText)

                Text("•")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LogbookStyle.subtleText.opacity(0.55))

                Text(ActivityFormatting.sessionTime.string(from: review.startedAt, to: review.endedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(LogbookStyle.subtleText)
            }

            HStack(spacing: 10) {
                if allowNextSession {
                    Button("Start next session") {
                        model.startNextSession()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if allowRetry {
                    Button {
                        model.retryLastReview()
                    } label: {
                        Label("Retry review", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func sessionTimelineOnly(detail: StoredSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.session.goal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LogbookStyle.subtleText)

                    Text(historySessionStamp(startedAt: detail.session.startedAt, endedAt: detail.session.endedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(LogbookStyle.subtleText.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 8) {
                    chromeActionButton("Retry", systemImage: "arrow.clockwise") {
                        model.reviewSelectedHistorySessionAgain()
                    }

                    chromeActionButton("Delete", systemImage: "trash") {
                        model.deleteHistorySession(detail.session.id)
                    }
                }
            }
            Text(detail.session.goal)
                .font(.system(size: 20, weight: .semibold))
            if let summary = detail.session.summary {
                MarkdownText(summary, font: .system(size: 13), color: LogbookStyle.subtleText)
            }
        }
        .padding(.horizontal, 12)
    }

    private func historySessionStamp(startedAt: Date, endedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: startedAt)) · \(ActivityFormatting.sessionTime.string(from: startedAt, to: endedAt))"
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
                        .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func openAIActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LogbookStyle.badgeFill)
                )
                .overlay(
                    Capsule()
                        .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func liveActivityPanel(session: FocusSession) -> some View {
        let events = liveSessionEvents(for: session)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showLiveActivity.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showLiveActivity ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LogbookStyle.subtleText)
                    Text("Activity being captured")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LogbookStyle.text)
                    Spacer()
                    Text("\(model.activeSessionEventCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LogbookStyle.subtleText)
                }
            }
            .buttonStyle(.plain)

            if showLiveActivity {
                if events.isEmpty {
                    Text("No live activity captured yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(LogbookStyle.subtleText)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(events) { event in
                                liveActivityRow(event)
                            }
                        }
                    }
                    .frame(maxHeight: 168)
                }
            }
        }
        .padding(.top, 4)
    }

    private func liveActivityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ActivityFormatting.shortTime.string(from: event.occurredAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(LogbookStyle.subtleText)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(liveEventTitle(for: event))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LogbookStyle.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let metadata = liveEventMetadata(for: event) {
                    Text(metadata)
                        .font(.system(size: 11))
                        .foregroundStyle(LogbookStyle.subtleText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func liveSessionEvents(for session: FocusSession) -> [ActivityEvent] {
        model.allEvents
            .filter { $0.occurredAt >= session.startedAt && $0.occurredAt <= Date() }
            .suffix(18)
            .map { $0 }
    }

    private func liveEventTitle(for event: ActivityEvent) -> String {
        switch event.kind {
        case .appActivated:
            return "Switched to \(event.appName ?? "another app")"
        case .appLaunched:
            return "Opened \(event.appName ?? "an app")"
        case .appTerminated:
            return "Closed \(event.appName ?? "an app")"
        case .windowChanged:
            return event.windowTitle ?? event.resourceTitle ?? "Changed window"
        case .tabFocused, .tabChanged:
            return event.resourceTitle ?? event.windowTitle ?? "Changed browser tab"
        case .commandStarted:
            return event.command ?? "Started command"
        case .commandFinished:
            return event.command ?? "Finished command"
        case .fileCreated:
            return "Created \(event.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file")"
        case .fileModified:
            return "Edited \(event.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file")"
        case .fileRenamed:
            return "Renamed \(event.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file")"
        case .fileDeleted:
            return "Deleted \(event.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "file")"
        case .clipboardChanged:
            return "Clipboard changed"
        case .userIdle:
            return "Went idle"
        case .userResumed:
            return "Returned"
        case .systemWoke:
            return "Mac woke up"
        case .systemSlept:
            return "Mac went to sleep"
        case .capturePaused:
            return "Capture paused"
        case .captureResumed:
            return "Capture resumed"
        case .noteAdded:
            return event.noteText ?? "Added note"
        case .sessionPinned:
            return "Pinned session"
        }
    }

    private func liveEventMetadata(for event: ActivityEvent) -> String? {
        var parts: [String] = []

        if let app = event.appName, !app.isEmpty {
            parts.append(app)
        }

        if let domain = event.domain, !domain.isEmpty {
            parts.append(domain)
        } else if let url = event.resourceURL, let host = URL(string: url)?.host(), !host.isEmpty {
            parts.append(host)
        }

        if let path = event.path, !path.isEmpty {
            parts.append(URL(fileURLWithPath: path).lastPathComponent)
        }

        if let title = event.resourceTitle,
           !title.isEmpty,
           title != event.windowTitle {
            parts.append(title)
        }

        if let preview = event.clipboardPreview,
           !preview.isEmpty {
            parts.append(String(preview.prefix(72)))
        }

        if let directory = event.workingDirectory,
           !directory.isEmpty {
            parts.append(URL(fileURLWithPath: directory).lastPathComponent)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func syncSessionGoalDraftFromModel() {
        guard model.surfaceState == .setup else { return }
        if !goalFieldFocused || sessionGoalDraft.isEmpty {
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
    private func bullet(text: String, spans: [SessionReviewInlineSpan] = []) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            RichReviewText(
                spans: spans,
                fallbackMarkdown: text,
                font: .system(size: 13),
                color: LogbookStyle.subtleText
            )
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

        if segment.appName == "Log Book" && primary.contains("break") {
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
            if let note = group.first(where: { $0.appName == "Log Book" })?.primaryLabel.lowercased(), note.contains("1 min") || note.contains("1-minute") || note.contains("1 minute") {
                return "Took a 1-minute break"
            }
            if group.first(where: { $0.appName == "Log Book" })?.primaryLabel != nil {
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
        if style == .breakState, let note = group.first(where: { $0.appName == "Log Book" })?.primaryLabel {
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

private struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection("Ollama") {
                        settingsTextField(title: "Base URL", text: $model.ollamaBaseURLInput)
                        settingsTextField(title: "Model", text: $model.ollamaModelName)
                        settingsTextField(title: "Timeout (seconds)", text: $model.ollamaTimeoutInput)
                        Toggle("Store model prompt and raw response for debugging", isOn: $model.ollamaStoreDebugIO)

                        HStack(spacing: 10) {
                            Button("Refresh local models") {
                                Task { await model.refreshAvailableModels() }
                            }
                            .buttonStyle(.bordered)

                            if !model.availableOllamaModels.isEmpty {
                                Picker("Detected models", selection: $model.ollamaModelName) {
                                    ForEach(model.availableOllamaModels) { model in
                                        Text(model.name).tag(model.name)
                                    }
                                }
                                .frame(maxWidth: 320)
                            }
                        }

                        if !model.ollamaStatusMessage.isEmpty {
                            InlineMessage(
                                text: model.ollamaStatusMessage,
                                tint: model.ollamaStatusIsError ? LogbookStyle.warning : LogbookStyle.success
                            )
                        }
                    }

                    settingsSection("Capture") {
                        Toggle("Window titles", isOn: $model.trackAccessibilityTitles)
                        Toggle("Browser context", isOn: $model.trackBrowserContext)
                        Toggle("Finder context", isOn: $model.trackFinderContext)
                        Toggle("Shell commands", isOn: $model.trackShellCommands)
                        Toggle("File activity", isOn: $model.trackFileSystemActivity)
                        Toggle("Clipboard", isOn: $model.trackClipboard)
                        Toggle("Presence", isOn: $model.trackPresence)
                        Toggle("Calendar context", isOn: $model.trackCalendarContext)
                        settingsTextField(title: "Raw event retention (days)", text: $model.rawEventRetentionDaysInput)
                    }

                    settingsSection("Permissions") {
                        permissionRow(title: "Accessibility", subtitle: model.accessibilityTrusted ? "Enabled" : "Not enabled") {
                            model.requestAccessibilityAccess()
                        }
                        permissionRow(title: "Calendar", subtitle: model.calendarAccessDescription) {
                            model.requestCalendarAccess()
                        }
                    }

                    settingsSection("Privacy rules") {
                        settingsEditor(title: "File watch roots", text: $model.fileWatchRootsInput)
                        settingsEditor(title: "Exclude app bundle IDs", text: $model.excludedAppBundleIDsInput)
                        settingsEditor(title: "Exclude browser domains", text: $model.excludedDomainsInput)
                        settingsEditor(title: "Exclude path prefixes", text: $model.excludedPathPrefixesInput)
                        settingsEditor(title: "Redact window titles for bundle IDs", text: $model.redactedTitleBundleIDsInput)
                        settingsEditor(title: "Drop shell commands for directory prefixes", text: $model.droppedShellDirectoryPrefixesInput)
                        settingsEditor(title: "Summary-only browser domains", text: $model.summaryOnlyDomainsInput)
                    }

                    settingsSection("Privacy statement") {
                        Text("Log Book captures local app, title, browser, shell, file, note, clipboard-preview, and calendar context only when those sources are enabled. It never captures screenshots, OCR, audio, camera, microphone, or keystrokes. AI reviews are generated locally through Ollama on localhost only.")
                            .font(.system(size: 12))
                            .foregroundStyle(LogbookStyle.subtleText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingsSection("Storage") {
                        storagePath(model.databasePath)
                        storagePath(LogbookPaths.shellInboxURL.path)
                    }

                    HStack(spacing: 10) {
                        Button("Save settings") {
                            model.saveCaptureSettings()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Clear raw events") {
                            model.clearAllEvents()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear model debug data") {
                            model.clearModelDebugData()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let errorMessage = model.errorMessage, !errorMessage.isEmpty {
                        InlineMessage(text: errorMessage, tint: LogbookStyle.warning)
                    }
                }
                .padding(18)
                .frame(maxWidth: 540, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        model.saveCaptureSettings()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 560, height: 500)
        .preferredColorScheme(.dark)
        .task {
            await model.refreshAvailableModels()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Card(secondary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
            }
        }
    }

    private func permissionRow(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(LogbookStyle.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Request", action: action)
                .buttonStyle(.bordered)
        }
    }

    private func settingsTextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LogbookStyle.inputFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                )
        }
    }

    private func settingsEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 72)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LogbookStyle.inputFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(LogbookStyle.cardStroke, lineWidth: 1)
                        )
                )
        }
    }

    private func storagePath(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(LogbookStyle.subtleText)
            .textSelection(.enabled)
    }
}

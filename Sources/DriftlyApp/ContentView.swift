import DriftlyCore
import SwiftUI

enum ActiveSheet: Identifiable {
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
    @State var activeSheet: ActiveSheet?
    @State private var activePane: MainPane = .session
    @State var sessionGoalDraft = ""
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

            if !model.reviewProviderStatusDidLoad {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                        .tint(DriftlyStyle.subtleText.opacity(0.42))

                    Text("Checking setup…")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DriftlyStyle.subtleText.opacity(0.52))
                }
            }

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

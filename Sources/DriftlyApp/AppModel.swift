import AppKit
import Combine
import Foundation
import DriftlyCore
import UserNotifications

enum SessionScreenState: String, Equatable {
    case setup
    case running
    case generatingReview
    case reviewReady
}

enum PermissionOnboardingKind: String, Identifiable {
    case accessibility

    var id: String { rawValue }
}

struct PermissionOnboardingItem: Identifiable {
    let kind: PermissionOnboardingKind
    let title: String
    let status: String
    let detail: String
    let actionTitle: String
    let isSatisfied: Bool

    var id: String { kind.rawValue }
}

private final class PermissionRefreshTimerTarget: NSObject {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    @MainActor
    @objc func tick(_ timer: Timer) {
        guard let model else {
            timer.invalidate()
            return
        }

        model.handlePermissionRefreshTick(timer)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var allEvents: [ActivityEvent]
    @Published var sessionDraftTitle = ""
    @Published var sessionDurationMinutes = 45
    @Published var sessionDurationInput = "45"
    @Published var quickNoteInput = ""
    @Published var captureEnabled = true
    @Published var trackAccessibilityTitles = true
    @Published var trackBrowserContext = true
    @Published var trackFinderContext = true
    @Published var trackShellCommands = true
    @Published var trackFileSystemActivity = true
    @Published var trackClipboard = true
    @Published var trackPresence = true
    @Published var focusGuardEnabled = true
    @Published var focusGuardPreset: FocusGuardPreset = .balanced
    @Published var fileWatchRootsInput = ""
    @Published var excludedAppBundleIDsInput = ""
    @Published var excludedDomainsInput = ""
    @Published var excludedPathPrefixesInput = ""
    @Published var redactedTitleBundleIDsInput = ""
    @Published var droppedShellDirectoryPrefixesInput = ""
    @Published var summaryOnlyDomainsInput = ""
    @Published var reviewProviderSelection: AIReviewProvider = .appDefault
    @Published var codexModelName = ""
    @Published var claudeModelName = ""
    @Published var chatCLITimeoutInput = "90"
    @Published var chatCLIStoreDebugIO = false
    @Published var dailySummaryEnabled = false
    @Published var dailySummaryTime = Date()
    @Published var weeklySummaryEnabled = false
    @Published var weeklySummaryWeekday = 1
    @Published var weeklySummaryTime = Date()
    @Published var summaryNotifyWhenReady = true
    @Published var rawEventRetentionDaysInput = "30"
    @Published var errorMessage: String?
    @Published private(set) var activeSession: FocusSession?
    @Published private(set) var lastSessionReview: SessionReview?
    @Published private(set) var lastSessionReviewPrompt = ""
    @Published private(set) var lastSessionReviewRawResponse = ""
    @Published private(set) var lastSessionReviewProvider = ""
    @Published private(set) var lastReviewErrorMessage: String?
    @Published private(set) var surfaceState: SessionScreenState = .setup
    @Published private(set) var accessibilityTrustedState: Bool
    @Published private(set) var reviewProviderStatusMessage = ""
    @Published private(set) var reviewProviderStatusIsError = false
    @Published private(set) var reviewProviderStatusDidLoad = false
    @Published private(set) var codexCLIStatus = ChatCLIStatus(installed: false, authenticated: false, version: nil, message: "")
    @Published private(set) var claudeCLIStatus = ChatCLIStatus(installed: false, authenticated: false, version: nil, message: "")
    @Published private(set) var activeSessionEventCount = 0
    @Published private(set) var historySessions: [StoredSession] = []
    @Published private(set) var selectedHistoryDetail: StoredSessionDetail?
    @Published private(set) var selectedPeriodicSummaryKind: StoredPeriodicSummaryKind?
    @Published private(set) var selectedPeriodicSummaryID: String?
    @Published private(set) var latestDailySummary: StoredPeriodicSummary?
    @Published private(set) var latestWeeklySummary: StoredPeriodicSummary?
    @Published private(set) var dailySummaryHistory: [StoredPeriodicSummary] = []
    @Published private(set) var weeklySummaryHistory: [StoredPeriodicSummary] = []
    @Published private(set) var periodicSummaryInFlightKinds: Set<StoredPeriodicSummaryKind> = []
    @Published private(set) var reviewInFlightSessionID: String?
    @Published private(set) var latestSessionID: String?
    @Published var showPermissionOnboarding = true
    @Published private(set) var focusGuardSettings = FocusGuardSettings()
    @Published private(set) var focusGuardAssessment = FocusGuardAssessment.empty
    @Published private(set) var activeFocusGuardPrompt: FocusGuardPrompt?
    @Published private(set) var settingsSheetRequestID = 0

    private let monitor = ActivityMonitor()
    private let fileMonitor = FileActivityMonitor()
    private let store = SessionStore()
    private let focusGuardNotifications = FocusGuardNotificationCoordinator()
    private let reviewDisplayName: String?
    private var shellImportTimer: Timer?
    private var sessionTimer: Timer?
    private var permissionRefreshTimer: Timer?
    private var permissionRefreshTimerTarget: PermissionRefreshTimerTarget?
    private var reviewProviderRefreshTask: Task<Void, Never>?
    private var captureSettings: CaptureSettings
    private var completedSessionContext: CompletedSessionContext?
    private let memoryEventLimit = 5_000
    private var notificationObservers: [NSObjectProtocol] = []
    private let focusGuardReminderInterval: TimeInterval = 2 * 60
    private var nextFocusGuardEvaluationAt: Date?
    private var focusGuardRuntimeState = FocusGuardRuntimeState()

    init() {
        self.captureSettings = store.loadCaptureSettings()
        self.allEvents = store.recentEvents()
        self.accessibilityTrustedState = AccessibilityInspector.isTrusted(prompt: false)
        self.reviewDisplayName = Self.preferredReviewDisplayName()
        applyCaptureSettings(captureSettings)
        self.fileWatchRootsInput = Self.multilineList(from: captureSettings.fileWatchRoots)
        self.excludedAppBundleIDsInput = Self.multilineList(from: captureSettings.excludedAppBundleIDs)
        self.excludedDomainsInput = Self.multilineList(from: captureSettings.excludedDomains)
        self.excludedPathPrefixesInput = Self.multilineList(from: captureSettings.excludedPathPrefixes)
        self.redactedTitleBundleIDsInput = Self.multilineList(from: captureSettings.redactedTitleBundleIDs)
        self.droppedShellDirectoryPrefixesInput = Self.multilineList(from: captureSettings.droppedShellDirectoryPrefixes)
        self.summaryOnlyDomainsInput = Self.multilineList(from: captureSettings.summaryOnlyDomains)
        self.reviewProviderSelection = captureSettings.reviewProvider
        self.codexModelName = captureSettings.chatCLI.resolvedCodexModelName
        self.claudeModelName = captureSettings.chatCLI.resolvedClaudeModelName
        self.chatCLITimeoutInput = String(captureSettings.chatCLI.timeoutSeconds)
        self.chatCLIStoreDebugIO = captureSettings.chatCLI.storeDebugIO
        self.dailySummaryEnabled = captureSettings.summaryAutomation.dailyEnabled
        self.dailySummaryTime = Self.timePickerDate(
            hour: captureSettings.summaryAutomation.dailyHour,
            minute: captureSettings.summaryAutomation.dailyMinute
        )
        self.weeklySummaryEnabled = captureSettings.summaryAutomation.weeklyEnabled
        self.weeklySummaryWeekday = captureSettings.summaryAutomation.weeklyWeekday
        self.weeklySummaryTime = Self.timePickerDate(
            hour: captureSettings.summaryAutomation.weeklyHour,
            minute: captureSettings.summaryAutomation.weeklyMinute
        )
        self.summaryNotifyWhenReady = captureSettings.summaryAutomation.notifyWhenReady
        self.rawEventRetentionDaysInput = String(captureSettings.rawEventRetentionDays)
        self.focusGuardNotifications.onAction = { [weak self] action, sessionID in
            Task { @MainActor [weak self] in
                self?.handleFocusGuardNotificationAction(action, sessionID: sessionID)
            }
        }

        monitor.onEvent = { [weak self] event in
            self?.append(event)
        }
        fileMonitor.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.append(event)
            }
        }
        refreshHistory()
        refreshPeriodicSummaries()
        hydrateLatestSession()
        if let startupError = store.startupError {
            assignErrorMessage(startupError)
        }
        installPermissionObservers()
        reconcilePermissionRefreshTimer()
        start()
        Task { [weak self] in
            await self?.refreshReviewProviderStatus()
            await self?.runPendingPeriodicSummariesIfNeeded()
        }
    }

    deinit {
        permissionRefreshTimer?.invalidate()
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    var accessibilityTrusted: Bool {
        accessibilityTrustedState
    }

    var databasePath: String {
        store.databasePath
    }

    private func assignErrorMessage(_ error: Error) {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = message.lowercased()
        if lowered.contains("database is locked") || lowered.contains("database locked") || lowered.contains("database busy") {
            errorMessage = nil
            return
        }
        errorMessage = message.isEmpty ? nil : message
    }

    var sessionGoalIsValid: Bool {
        !sessionDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var accessibilityAccessDescription: String {
        guard trackAccessibilityTitles else {
            return "Window titles are off in Settings."
        }

        if accessibilityTrusted {
            return "Window titles and stronger app context are enabled."
        }

        return "Enable Accessibility to capture active window titles and improve session evidence."
    }

    var localReviewConfigured: Bool {
        switch reviewProviderSelection {
        case .codex:
            return codexCLIStatus.installed && codexCLIStatus.authenticated
        case .claude:
            return claudeCLIStatus.installed && claudeCLIStatus.authenticated
        }
    }

    var reviewProviderSelectionLabel: String {
        switch reviewProviderSelection {
        case .codex:
            return "Codex (local ChatGPT login)"
        case .claude:
            return "Claude Code"
        }
    }

    var selectedChatCLITool: ChatCLITool {
        switch reviewProviderSelection {
        case .codex:
            return .codex
        case .claude:
            return .claude
        }
    }

    var selectedChatCLIStatus: ChatCLIStatus {
        switch selectedChatCLITool {
        case .codex:
            return codexCLIStatus
        case .claude:
            return claudeCLIStatus
        }
    }

    var selectedProviderNeedsSetup: Bool {
        let status = selectedChatCLIStatus
        return !status.installed || !status.authenticated
    }

    var selectedProviderSetupActionTitle: String {
        selectedChatCLITool.setupActionTitle
    }

    var reviewProviderIntroText: String {
        switch reviewProviderSelection {
        case .codex:
            return "Driftly will use the local Codex CLI signed in on this Mac. In this setup, the login is your ChatGPT-backed Codex account."
        case .claude:
            return "Driftly will use the local Claude Code CLI signed in on this Mac."
        }
    }

    var codexModelCompatibilityMessage: String? {
        guard reviewProviderSelection == .codex else { return nil }
        switch normalizedCodexModelName {
        case "gpt-5-codex", "codex-mini-latest":
            return "This model is currently rejected by the local ChatGPT-backed Codex login on this Mac. GPT-5.4 is the known working option."
        default:
            return nil
        }
    }

    var hasRunningSession: Bool {
        activeSession != nil
    }

    func sessionRemainingLabel(now: Date = Date()) -> String? {
        guard let activeSession else { return nil }
        let remaining = max(Int(activeSession.endsAt.timeIntervalSince(now)), 0)
        let minutes = remaining / 60
        let seconds = remaining % 60

        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    func sessionElapsedLabel(now: Date = Date()) -> String? {
        guard let activeSession else { return nil }
        let elapsed = max(Int(now.timeIntervalSince(activeSession.startedAt)), 0)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    var localReviewSetupSummary: String {
        switch reviewProviderSelection {
        case .codex:
            return codexCLIStatus.message.isEmpty ? "Codex with the local ChatGPT login is not ready for AI review yet." : codexCLIStatus.message
        case .claude:
            return claudeCLIStatus.message.isEmpty ? "Claude Code is not ready for AI review yet." : claudeCLIStatus.message
        }
    }

    var accessibilitySetupSummary: String? {
        guard trackAccessibilityTitles, !accessibilityTrusted else { return nil }
        return "so Driftly can give you the best experience."
    }

    var permissionOnboardingItems: [PermissionOnboardingItem] {
        let accessibilityItem: PermissionOnboardingItem = {
            if !trackAccessibilityTitles {
                return PermissionOnboardingItem(
                    kind: .accessibility,
                    title: "Accessibility",
                    status: "Disabled in Settings",
                    detail: "Window titles are off, so Accessibility is optional right now.",
                    actionTitle: "Open settings",
                    isSatisfied: true
                )
            }

            if accessibilityTrusted {
                return PermissionOnboardingItem(
                    kind: .accessibility,
                    title: "Accessibility",
                    status: "Enabled",
                    detail: "Window titles and richer app context can be captured during sessions.",
                    actionTitle: "Review",
                    isSatisfied: true
                )
            }

            return PermissionOnboardingItem(
                kind: .accessibility,
                title: "Accessibility",
                status: "Recommended",
                detail: "Needed for window titles, editor file titles, browser page titles, and more useful timeline labels.",
                actionTitle: "Open System Settings",
                isSatisfied: false
            )
        }()

        return [accessibilityItem]
    }

    var shouldShowPermissionOnboarding: Bool {
        showPermissionOnboarding && permissionOnboardingItems.contains(where: { !$0.isSatisfied })
    }

    var permissionOnboardingSummary: String {
        let missing = permissionOnboardingItems.filter { !$0.isSatisfied }
        guard !missing.isEmpty else {
            return "All recommended permissions are enabled."
        }

        if missing.count == 1, let item = missing.first {
            return "\(item.title) is the only missing piece. You can still start a session now."
        }

        return "\(missing.count) permissions are still missing. Driftly will work, but the review will be less detailed."
    }

    var enabledCaptureLabels: [String] {
        var labels = ["apps", "system"]
        if trackAccessibilityTitles { labels.append("titles") }
        if trackBrowserContext { labels.append("browser") }
        if trackFinderContext { labels.append("Finder") }
        if trackShellCommands { labels.append("shell") }
        if trackFileSystemActivity { labels.append("files") }
        if trackClipboard { labels.append("clipboard") }
        if trackPresence { labels.append("presence") }
        return labels
    }

    var evidenceStatusText: String {
        if surfaceState == .generatingReview {
            return "Building the timeline and generating your session review."
        }

        if let activeSession {
            return "\(activeSessionEventCount) events captured for \(activeSession.title)."
        }

        return "Ready to capture \(enabledCaptureLabels.joined(separator: ", "))."
    }

    var focusGuardStatusText: String {
        focusGuardAssessment.status.title
    }

    func start() {
        guard captureEnabled else { return }
        monitor.start()
        refreshFileMonitorRoots()
        startShellImport()
        importShellCommands()
        do {
            try store.pruneRawEvents(olderThan: captureSettings.rawEventRetentionDays)
        } catch {
            assignErrorMessage(error)
        }
    }

    func stop() {
        monitor.stop()
        fileMonitor.stop()
        shellImportTimer?.invalidate()
        shellImportTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    func toggleCapture() {
        captureEnabled.toggle()
        append(
            ActivityEvent(
                occurredAt: Date(),
                source: .system,
                kind: captureEnabled ? .captureResumed : .capturePaused,
                appName: "Driftly"
            )
        )

        if captureEnabled {
            start()
        } else {
            stop()
        }
    }

    func requestAccessibilityAccess() {
        AccessibilityInspector.openSettings()
        _ = AccessibilityInspector.isTrusted(prompt: true)
        refreshPermissionStatuses()
        reconcilePermissionRefreshTimer()
    }

    func openAccessibilitySettings() {
        AccessibilityInspector.openSettings()
        reconcilePermissionRefreshTimer()
    }

    func openChatCLIInstallGuide(for tool: ChatCLITool) {
        NSWorkspace.shared.open(tool.installGuideURL)
    }

    func openChatCLILogin(for tool: ChatCLITool) {
        let command = tool.loginCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        _ = AppleScriptRunner.run(
            """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """,
            timeout: 1.5
        )
        beginReviewProviderStatusPolling()
    }

    func openSelectedReviewProviderSetup() {
        openChatCLILogin(for: selectedChatCLITool)
    }

    func performPermissionOnboardingAction(for kind: PermissionOnboardingKind) {
        switch kind {
        case .accessibility:
            if trackAccessibilityTitles, !accessibilityTrusted {
                requestAccessibilityAccess()
            } else {
                hidePermissionOnboarding()
            }
        }
    }

    func hidePermissionOnboarding() {
        showPermissionOnboarding = false
    }

    func refreshAvailableModels() async {
        await refreshReviewProviderStatus()
    }

    func refreshReviewProviderStatus() async {
        reviewProviderStatusDidLoad = false
        let detectedCodex = await Task.detached(priority: .userInitiated) {
            ChatCLIReviewRunner.detect(tool: .codex)
        }.value
        let detectedClaude = await Task.detached(priority: .userInitiated) {
            ChatCLIReviewRunner.detect(tool: .claude)
        }.value
        codexCLIStatus = detectedCodex
        claudeCLIStatus = detectedClaude

        switch reviewProviderSelection {
        case .codex:
            let configuredModel = currentChatCLIConfiguration().codexModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if detectedCodex.installed && detectedCodex.authenticated {
                if let compatibilityMessage = codexModelCompatibilityMessage {
                    reviewProviderStatusMessage = compatibilityMessage
                    reviewProviderStatusIsError = true
                } else {
                    reviewProviderStatusMessage = configuredModel.isEmpty
                        ? "Codex CLI is installed and signed in with your local ChatGPT login. Using its default model."
                        : "Codex CLI is installed and signed in with your local ChatGPT login. Using \(configuredModel)."
                    reviewProviderStatusIsError = false
                }
            } else {
                reviewProviderStatusMessage = detectedCodex.message
                reviewProviderStatusIsError = true
            }
        case .claude:
            let configuredModel = currentChatCLIConfiguration().claudeModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if detectedClaude.installed && detectedClaude.authenticated {
                reviewProviderStatusMessage = configuredModel.isEmpty
                    ? "Claude Code is installed and signed in. Using its default model."
                    : "Claude Code is installed and signed in. Using \(configuredModel)."
                reviewProviderStatusIsError = false
            } else {
                reviewProviderStatusMessage = detectedClaude.message
                reviewProviderStatusIsError = true
            }
        }
        reviewProviderStatusDidLoad = true
    }

    private func beginReviewProviderStatusPolling() {
        reviewProviderRefreshTask?.cancel()
        reviewProviderRefreshTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<12 {
                if Task.isCancelled { return }
                if attempt > 0 {
                    try? await Task.sleep(for: .seconds(2))
                }
                await self.refreshReviewProviderStatus()
                if self.selectedChatCLIStatus.authenticated {
                    return
                }
            }
        }
    }

    func startSession() {
        syncSessionDurationFromInput()
        let trimmedTitle = sessionDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Enter a session goal before starting."
            return
        }

        let startedAt = Date()
        let endsAt = startedAt.addingTimeInterval(TimeInterval(sessionDurationMinutes * 60))
        activeSession = FocusSession(
            title: trimmedTitle,
            durationMinutes: sessionDurationMinutes,
            startedAt: startedAt,
            endsAt: endsAt
        )
        activeSessionEventCount = 0
        quickNoteInput = ""
        lastReviewErrorMessage = nil
        surfaceState = .running
        resetFocusGuardState()
        if focusGuardPreset != .off {
            nextFocusGuardEvaluationAt = startedAt.addingTimeInterval(focusGuardReminderInterval)
        }
        startSessionTimer()
        if focusGuardPreset != .off {
            Task { [focusGuardNotifications] in
                _ = await focusGuardNotifications.requestAuthorizationIfNeeded()
            }
        }
    }

    func endSessionNow() {
        finishSession(endedAt: Date())
    }

    func startNextSession() {
        surfaceState = .setup
        quickNoteInput = ""
        lastReviewErrorMessage = nil
        resetFocusGuardState()
    }

    func retryLastReview() {
        guard let context = completedSessionContext else { return }
        reviewInFlightSessionID = context.sessionID
        surfaceState = .generatingReview
        lastReviewErrorMessage = nil
        performReview(for: context)
    }

    func reviewSelectedHistorySessionAgain() {
        guard let detail = selectedHistoryDetail else { return }
        reviewInFlightSessionID = detail.session.id
        let events = store.events(between: detail.session.startedAt, and: detail.session.endedAt)
        let evidenceEvents = events.filter { !$0.kind.isFocusGuardSignal }
        let segments = TimelineDeriver.deriveSegments(from: evidenceEvents, sessionEnd: detail.session.endedAt)
        let context = CompletedSessionContext(
            sessionID: detail.session.id,
            title: detail.session.goal,
            startedAt: detail.session.startedAt,
            endedAt: detail.session.endedAt,
            events: events,
            segments: segments
        )
        performReview(for: context)
    }

    func addQuickNote() {
        let trimmed = quickNoteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        append(
            ActivityEvent(
                occurredAt: Date(),
                source: .manual,
                kind: .noteAdded,
                appName: "Driftly",
                noteText: trimmed,
                relatedID: activeSession?.id
            )
        )
        quickNoteInput = ""
    }

    func clearAllEvents() {
        do {
            try store.clearAllEvents()
            allEvents = []
            activeSessionEventCount = 0
            refreshFileMonitorRoots()
            errorMessage = nil
        } catch {
            assignErrorMessage(error)
        }
    }

    func clearModelDebugData() {
        do {
            try store.clearModelDebugData()
            refreshHistory()
            hydrateLatestSession()
            errorMessage = nil
        } catch {
            assignErrorMessage(error)
        }
    }

    func deleteHistorySession(_ id: String) {
        do {
            try store.deleteSession(id: id)
            if reviewInFlightSessionID == id {
                reviewInFlightSessionID = nil
            }
            refreshHistory()
            hydrateLatestSession()
            errorMessage = nil
        } catch {
            assignErrorMessage(error)
        }
    }

    func saveCaptureSettings() {
        let retentionDays = max(Int(rawEventRetentionDaysInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30, 1)
        let resolvedFocusPreset: FocusGuardPreset = focusGuardEnabled ? .balanced : .off
        let dailyComponents = Self.hourMinute(from: dailySummaryTime)
        let weeklyComponents = Self.hourMinute(from: weeklySummaryTime)

        captureSettings = CaptureSettings(
            focusGuardEnabled: resolvedFocusPreset != .off,
            focusGuardPreset: resolvedFocusPreset,
            trackAccessibilityTitles: trackAccessibilityTitles,
            trackBrowserContext: trackBrowserContext,
            trackFinderContext: trackFinderContext,
            trackShellCommands: trackShellCommands,
            trackFileSystemActivity: trackFileSystemActivity,
            trackClipboard: trackClipboard,
            trackPresence: trackPresence,
            fileWatchRoots: Self.parseMultilineList(fileWatchRootsInput),
            excludedAppBundleIDs: Self.parseMultilineList(excludedAppBundleIDsInput),
            excludedDomains: Self.parseMultilineList(excludedDomainsInput),
            excludedPathPrefixes: Self.parseMultilineList(excludedPathPrefixesInput),
            redactedTitleBundleIDs: Self.parseMultilineList(redactedTitleBundleIDsInput),
            droppedShellDirectoryPrefixes: Self.parseMultilineList(droppedShellDirectoryPrefixesInput),
            summaryOnlyDomains: Self.parseMultilineList(summaryOnlyDomainsInput),
            rawEventRetentionDays: retentionDays,
            reviewProvider: normalizedReviewProviderSelection,
            chatCLI: ChatCLIConfiguration(
                codexModelName: normalizedCodexModelName,
                claudeModelName: normalizedClaudeModelName,
                timeoutSeconds: normalizedChatCLITimeoutSeconds,
                storeDebugIO: chatCLIStoreDebugIO
            ),
            summaryAutomation: SummaryAutomationSettings(
                dailyEnabled: dailySummaryEnabled,
                dailyHour: dailyComponents.hour,
                dailyMinute: dailyComponents.minute,
                weeklyEnabled: weeklySummaryEnabled,
                weeklyWeekday: weeklySummaryWeekday,
                weeklyHour: weeklyComponents.hour,
                weeklyMinute: weeklyComponents.minute,
                notifyWhenReady: summaryNotifyWhenReady
            )
        )

        do {
            try store.saveCaptureSettings(captureSettings)
            try store.pruneRawEvents(olderThan: retentionDays)
            errorMessage = nil
        } catch {
            assignErrorMessage(error)
        }

        refreshFileMonitorRoots()
        focusGuardPreset = resolvedFocusPreset
        focusGuardEnabled = resolvedFocusPreset != .off
        focusGuardSettings = resolvedFocusPreset.settings
        if resolvedFocusPreset == .off {
            activeFocusGuardPrompt = nil
        }
        Task { [weak self] in
            await self?.refreshReviewProviderStatus()
            self?.refreshPeriodicSummaries()
            await self?.runPendingPeriodicSummariesIfNeeded()
        }
    }

    func setNudgesEnabled(_ enabled: Bool) {
        focusGuardEnabled = enabled
        focusGuardPreset = enabled ? .balanced : .off
    }

    private var normalizedChatCLITimeoutSeconds: Int {
        max(Int(chatCLITimeoutInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 90, 0)
    }

    private func currentChatCLIConfiguration() -> ChatCLIConfiguration {
        ChatCLIConfiguration(
            codexModelName: normalizedCodexModelName,
            claudeModelName: normalizedClaudeModelName,
            timeoutSeconds: normalizedChatCLITimeoutSeconds,
            storeDebugIO: chatCLIStoreDebugIO
        )
    }

    private var normalizedCodexModelName: String {
        let trimmed = codexModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ChatCLIConfiguration.preferredCodexModelName : trimmed
    }

    private var normalizedReviewProviderSelection: AIReviewProvider {
        reviewProviderSelection
    }

    private var normalizedClaudeModelName: String {
        let trimmed = claudeModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ChatCLIConfiguration.preferredClaudeModelName : trimmed
    }

    private func currentCaptureSettings() -> CaptureSettings {
        let dailyComponents = Self.hourMinute(from: dailySummaryTime)
        let weeklyComponents = Self.hourMinute(from: weeklySummaryTime)

        return CaptureSettings(
            focusGuardEnabled: captureSettings.focusGuardEnabled,
            focusGuardPreset: captureSettings.focusGuardPreset,
            trackAccessibilityTitles: captureSettings.trackAccessibilityTitles,
            trackBrowserContext: captureSettings.trackBrowserContext,
            trackFinderContext: captureSettings.trackFinderContext,
            trackShellCommands: captureSettings.trackShellCommands,
            trackFileSystemActivity: captureSettings.trackFileSystemActivity,
            trackClipboard: captureSettings.trackClipboard,
            trackPresence: captureSettings.trackPresence,
            fileWatchRoots: captureSettings.fileWatchRoots,
            excludedAppBundleIDs: captureSettings.excludedAppBundleIDs,
            excludedDomains: captureSettings.excludedDomains,
            excludedPathPrefixes: captureSettings.excludedPathPrefixes,
            redactedTitleBundleIDs: captureSettings.redactedTitleBundleIDs,
            droppedShellDirectoryPrefixes: captureSettings.droppedShellDirectoryPrefixes,
            summaryOnlyDomains: captureSettings.summaryOnlyDomains,
            rawEventRetentionDays: captureSettings.rawEventRetentionDays,
            reviewProvider: normalizedReviewProviderSelection,
            chatCLI: currentChatCLIConfiguration(),
            summaryAutomation: SummaryAutomationSettings(
                dailyEnabled: dailySummaryEnabled,
                dailyHour: dailyComponents.hour,
                dailyMinute: dailyComponents.minute,
                weeklyEnabled: weeklySummaryEnabled,
                weeklyWeekday: weeklySummaryWeekday,
                weeklyHour: weeklyComponents.hour,
                weeklyMinute: weeklyComponents.minute,
                notifyWhenReady: summaryNotifyWhenReady
            )
        )
    }

    func setSessionDuration(_ minutes: Int) {
        let rounded = Int((Double(minutes) / 5.0).rounded()) * 5
        let clamped = min(max(5, rounded), 120)
        sessionDurationMinutes = clamped
        sessionDurationInput = String(clamped)
    }

    func syncSessionDurationFromInput() {
        let trimmed = sessionDurationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed), parsed > 0 else {
            sessionDurationInput = String(sessionDurationMinutes)
            return
        }
        setSessionDuration(parsed)
    }

    func selectHistorySession(_ id: String) {
        selectedPeriodicSummaryKind = nil
        selectedPeriodicSummaryID = nil
        selectedHistoryDetail = store.sessionDetail(id: id)
    }

    func selectPeriodicSummary(_ kind: StoredPeriodicSummaryKind) {
        selectedPeriodicSummaryKind = kind
        selectedPeriodicSummaryID = periodicSummaryHistory(for: kind).first?.id
        selectedHistoryDetail = nil
    }

    func selectPeriodicSummary(_ summary: StoredPeriodicSummary) {
        selectedPeriodicSummaryKind = summary.kind
        selectedPeriodicSummaryID = summary.id
        selectedHistoryDetail = nil
    }

    func isPeriodicSummaryInFlight(_ kind: StoredPeriodicSummaryKind) -> Bool {
        periodicSummaryInFlightKinds.contains(kind)
    }

    func regenerateSelectedPeriodicSummary() {
        guard let summary = selectedPeriodicSummary() else { return }
        Task { [weak self] in
            await self?.regeneratePeriodicSummary(summary)
        }
    }

    func selectHistoryLibrary() {
        selectedPeriodicSummaryKind = nil
        selectedPeriodicSummaryID = nil
        ensureHistorySelection()
    }

    func ensureHistorySelection() {
        guard selectedPeriodicSummaryKind == nil else { return }

        if let selected = selectedHistoryDetail?.session.id,
           historySessions.contains(where: { $0.id == selected }) {
            return
        }

        guard let latest = historySessions.first else {
            selectedHistoryDetail = nil
            return
        }

        selectedHistoryDetail = store.sessionDetail(id: latest.id)
    }

    func clearHistorySelection() {
        selectedHistoryDetail = nil
    }

    func reviewFeedback(for sessionID: String) -> SessionReviewFeedback? {
        store.reviewFeedback(sessionID: sessionID)
    }

    func requestSettingsSheet() {
        settingsSheetRequestID += 1
    }

    func saveReviewFeedback(sessionID: String, review: SessionReview, wasHelpful: Bool, note: String? = nil) {
        do {
            try store.saveReviewFeedback(
                SessionReviewFeedback(
                    sessionID: sessionID,
                    wasHelpful: wasHelpful,
                    note: note,
                    goalSnapshot: review.sessionTitle,
                    reviewHeadlineSnapshot: review.headline,
                    reviewSummarySnapshot: review.summary,
                    reviewTakeawaySnapshot: review.focusAssessment
                )
            )
            errorMessage = nil
            Task { [weak self] in
                await self?.refreshReviewLearningMemory()
            }
        } catch {
            assignErrorMessage(error)
        }
    }

    func restorePrimarySessionSurface(preferred state: SessionScreenState? = nil) {
        func hasPrimaryReviewSurface() -> Bool {
            lastSessionReview != nil || !(lastReviewErrorMessage?.isEmpty ?? true)
        }

        if activeSession != nil {
            surfaceState = .running
            return
        }

        if surfaceState == .generatingReview {
            return
        }

        if let state {
            switch state {
            case .setup:
                surfaceState = .setup
                return
            case .reviewReady:
                hydrateLatestSession()
                surfaceState = hasPrimaryReviewSurface() ? .reviewReady : .setup
                return
            case .running:
                surfaceState = .setup
                return
            case .generatingReview:
                hydrateLatestSession()
                surfaceState = hasPrimaryReviewSurface() ? .reviewReady : .setup
                return
            }
        }

        hydrateLatestSession()
        surfaceState = hasPrimaryReviewSurface() ? .reviewReady : .setup
    }

    private func applyCaptureSettings(_ settings: CaptureSettings) {
        captureEnabled = true
        focusGuardPreset = settings.focusGuardPreset
        focusGuardEnabled = settings.focusGuardPreset != .off
        trackAccessibilityTitles = settings.trackAccessibilityTitles
        trackBrowserContext = settings.trackBrowserContext
        trackFinderContext = settings.trackFinderContext
        trackShellCommands = settings.trackShellCommands
        trackFileSystemActivity = settings.trackFileSystemActivity
        trackClipboard = settings.trackClipboard
        trackPresence = settings.trackPresence
        focusGuardSettings = settings.focusGuardPreset.settings
        refreshPermissionStatuses()
        reconcilePermissionRefreshTimer()
    }

    private func installPermissionObservers() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatuses()
                self?.reconcilePermissionRefreshTimer()
                await self?.refreshReviewProviderStatus()
                self?.refreshPeriodicSummaries()
                await self?.runPendingPeriodicSummariesIfNeeded()
            }
        }
        notificationObservers.append(observer)
    }

    private func refreshPermissionStatuses() {
        accessibilityTrustedState = AccessibilityInspector.isTrusted(prompt: false)
    }

    private func reconcilePermissionRefreshTimer() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
        permissionRefreshTimerTarget = nil

        guard trackAccessibilityTitles, !accessibilityTrustedState else { return }

        let target = PermissionRefreshTimerTarget(model: self)
        permissionRefreshTimerTarget = target
        permissionRefreshTimer = Timer.scheduledTimer(
            timeInterval: 2,
            target: target,
            selector: #selector(PermissionRefreshTimerTarget.tick(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    fileprivate func handlePermissionRefreshTick(_ timer: Timer) {
        refreshPermissionStatuses()
        if !trackAccessibilityTitles || accessibilityTrustedState {
            timer.invalidate()
            permissionRefreshTimer = nil
            permissionRefreshTimerTarget = nil
        }
    }

    private func startShellImport() {
        shellImportTimer?.invalidate()
        guard trackShellCommands else { return }

        shellImportTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.importShellCommands()
            }
        }
    }

    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let activeSession = self.activeSession else { return }
                self.activeSessionEventCount = self.eventCount(for: activeSession, endingAt: Date())
                self.evaluateFocusGuardIfNeeded(now: Date(), session: activeSession)
                if Date() >= activeSession.endsAt {
                    self.finishSession(endedAt: activeSession.endsAt)
                }
            }
        }
    }

    private func importShellCommands() {
        guard captureEnabled, trackShellCommands else { return }
        let knownIDs = Set(allEvents.map(\.id))
        let imported = ShellCommandImporter.importEvents(existingEventIDs: knownIDs, settings: captureSettings)
        guard !imported.isEmpty else { return }
        imported.sorted { $0.occurredAt < $1.occurredAt }.forEach(append(_:))
    }

    private func append(_ event: ActivityEvent) {
        guard let filteredEvent = PrivacyFilter.apply(to: event, settings: captureSettings) else {
            return
        }

        do {
            let inserted = try store.insertEvent(filteredEvent)
            guard inserted else { return }
            allEvents.append(filteredEvent)
            allEvents.sort { $0.occurredAt < $1.occurredAt }
            if allEvents.count > memoryEventLimit {
                allEvents = Array(allEvents.suffix(memoryEventLimit))
            }
            refreshFileMonitorRoots()
            if let activeSession {
                activeSessionEventCount = eventCount(for: activeSession, endingAt: Date())
            }
            errorMessage = nil
        } catch {
            assignErrorMessage(error)
        }
    }

    private func refreshFileMonitorRoots() {
        guard captureEnabled, trackFileSystemActivity else {
            fileMonitor.stop()
            return
        }

        let roots = captureSettings.fileWatchRoots.isEmpty
            ? deriveWatchRoots(from: allEvents)
            : captureSettings.fileWatchRoots
        fileMonitor.updateWatchedPaths(roots)
    }

    private func finishSession(endedAt: Date) {
        guard let activeSession else { return }

        sessionTimer?.invalidate()
        sessionTimer = nil
        self.activeSession = nil
        activeSessionEventCount = 0
        activeFocusGuardPrompt = nil
        nextFocusGuardEvaluationAt = nil
        surfaceState = .generatingReview

        let sessionEvents = store.events(between: activeSession.startedAt, and: endedAt)
        let evidenceEvents = sessionEvents.filter { !$0.kind.isFocusGuardSignal }
        let segments = TimelineDeriver.deriveSegments(from: evidenceEvents, sessionEnd: endedAt)
        let context = CompletedSessionContext(
            sessionID: activeSession.id,
            title: activeSession.title,
            startedAt: activeSession.startedAt,
            endedAt: endedAt,
            events: sessionEvents,
            segments: segments
        )
        completedSessionContext = context

        let pendingSession = StoredSession(
            id: context.sessionID,
            goal: context.title,
            startedAt: context.startedAt,
            endedAt: context.endedAt,
            reviewStatus: .pending,
            primaryLabels: TimelineDeriver.primaryLabels(from: segments)
        )
        do {
            try store.saveSession(pendingSession, review: nil, segments: segments, rawEventCount: sessionEvents.count)
            refreshHistory()
            performReview(for: context)
        } catch {
            completedSessionContext = nil
            surfaceState = .setup
            assignErrorMessage(error)
        }
    }

    private func performReview(for context: CompletedSessionContext) {
        reviewInFlightSessionID = context.sessionID
        guard !context.events.isEmpty else {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: context.title,
                error: "Not enough captured evidence to generate a review."
            )
            applyReviewFailure(
                sessionID: context.sessionID,
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                segments: context.segments,
                rawEventCount: context.events.count,
                reviewStatus: .failed,
                message: "Not enough captured evidence to generate a review."
            )
            return
        }

        let settings = currentCaptureSettings()
        if let setupIssue = reviewProviderSetupIssue(for: settings.reviewProvider) {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: context.title,
                error: setupIssue
            )
            applyReviewFailure(
                sessionID: context.sessionID,
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                segments: context.segments,
                rawEventCount: context.events.count,
                reviewStatus: .unavailable,
                message: setupIssue
            )
            return
        }

        Task {
            do {
                let provider = AIProviderBridge.provider(for: settings.reviewProvider)
                let run = try await provider.generateReview(
                    settings: settings,
                    title: context.title,
                    personName: reviewDisplayName,
                    contextPattern: nil,
                    insightWritingSkill: DriftlyAgentContext.skillName,
                    reviewLearnings: [],
                    feedbackExamples: [],
                    startedAt: context.startedAt,
                    endedAt: context.endedAt,
                    events: context.events,
                    segments: context.segments
                )
                applyCompletedReview(
                    enrichSessionReview(run.review, events: context.events, segments: context.segments),
                    sessionID: context.sessionID,
                    providerTitle: run.providerTitle,
                    prompt: shouldStoreDebugIO(for: settings.reviewProvider, settings: settings) ? run.prompt : "",
                    rawResponse: shouldStoreDebugIO(for: settings.reviewProvider, settings: settings) ? run.rawResponse : "",
                    reviewStatus: .ready,
                    rawEventCount: context.events.count
                )
            } catch {
                applyReviewFailure(
                    sessionID: context.sessionID,
                    title: context.title,
                    startedAt: context.startedAt,
                    endedAt: context.endedAt,
                    segments: context.segments,
                    rawEventCount: context.events.count,
                    reviewStatus: .failed,
                    message: error.localizedDescription,
                    prompt: shouldStoreDebugIO(for: settings.reviewProvider, settings: settings) ? "Review prompt failed." : "",
                    rawResponse: shouldStoreDebugIO(for: settings.reviewProvider, settings: settings) ? error.localizedDescription : ""
                )
            }
        }
    }

    private func applyReviewFailure(
        sessionID: String,
        title: String,
        startedAt: Date,
        endedAt: Date,
        segments: [TimelineSegment],
        rawEventCount: Int,
        reviewStatus: ReviewStatus,
        message: String,
        prompt: String = "",
        rawResponse: String = ""
    ) {
        reviewInFlightSessionID = nil
        lastSessionReview = nil
        lastSessionReviewProvider = ""
        lastSessionReviewPrompt = prompt
        lastSessionReviewRawResponse = rawResponse
        lastReviewErrorMessage = message
        surfaceState = .reviewReady
        resetFocusGuardState()

        let storedSession = StoredSession(
            id: sessionID,
            goal: title,
            startedAt: startedAt,
            endedAt: endedAt,
            reviewStatus: reviewStatus,
            primaryLabels: TimelineDeriver.primaryLabels(from: segments)
        )

        do {
            try store.saveSession(storedSession, review: nil, segments: segments, rawEventCount: rawEventCount)
            try store.clearSessionReview(sessionID: sessionID)
            latestSessionID = sessionID
            refreshHistory()
        } catch {
            assignErrorMessage(error)
        }
    }

    private func applyCompletedReview(
        _ review: SessionReview,
        sessionID: String,
        providerTitle: String,
        prompt: String,
        rawResponse: String,
        reviewStatus: ReviewStatus,
        rawEventCount: Int
    ) {
        reviewInFlightSessionID = nil
        lastSessionReview = review
        lastSessionReviewProvider = providerTitle
        lastSessionReviewPrompt = prompt
        lastSessionReviewRawResponse = rawResponse
        surfaceState = .reviewReady
        resetFocusGuardState()

        let storedSession = StoredSession(
            id: sessionID,
            goal: review.sessionTitle,
            startedAt: review.startedAt,
            endedAt: review.endedAt,
            verdict: review.verdict,
            headline: review.headline,
            summary: review.summary,
            reviewStatus: reviewStatus,
            primaryLabels: TimelineDeriver.primaryLabels(from: review.segments)
        )

        let storedReview = StoredSessionReview(
            sessionID: sessionID,
            providerTitle: providerTitle,
            review: review,
            debugPrompt: prompt.isEmpty ? nil : prompt,
            debugRawResponse: rawResponse.isEmpty ? nil : rawResponse
        )

        do {
            try store.saveSession(storedSession, review: storedReview, segments: review.segments, rawEventCount: rawEventCount)
            refreshHistory()
            refreshPeriodicSummaries()
            hydrateLatestSession()
            lastReviewErrorMessage = reviewStatus == .ready ? nil : lastReviewErrorMessage
            errorMessage = nil
            Task { [weak self] in
                await self?.runPendingPeriodicSummariesIfNeeded()
            }
        } catch {
            assignErrorMessage(error)
        }
    }

    private static func preferredReviewDisplayName() -> String? {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty,
           fullName.caseInsensitiveCompare("unknown") != .orderedSame {
            return fullName
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init)
        }

        let username = NSUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return username.isEmpty ? nil : username
    }

    private func refreshHistory() {
        historySessions = store.sessionHistory()
        if let selected = selectedHistoryDetail?.session.id {
            selectedHistoryDetail = store.sessionDetail(id: selected)
            if selectedHistoryDetail == nil {
                ensureHistorySelection()
            }
        } else {
            ensureHistorySelection()
        }
    }

    private func refreshPeriodicSummaries() {
        dailySummaryHistory = store.periodicSummaryHistory(kind: .daily)
        weeklySummaryHistory = store.periodicSummaryHistory(kind: .weekly)
        latestDailySummary = dailySummaryHistory.first
        latestWeeklySummary = weeklySummaryHistory.first

        if let selectedPeriodicSummaryKind {
            let available = periodicSummaryHistory(for: selectedPeriodicSummaryKind)
            if available.isEmpty {
                self.selectedPeriodicSummaryKind = nil
                self.selectedPeriodicSummaryID = nil
                ensureHistorySelection()
            } else if let selectedPeriodicSummaryID,
                      !available.contains(where: { $0.id == selectedPeriodicSummaryID }) {
                self.selectedPeriodicSummaryID = available.first?.id
            } else if selectedPeriodicSummaryID == nil {
                self.selectedPeriodicSummaryID = available.first?.id
            }
        }

        if selectedPeriodicSummaryKind == nil, selectedHistoryDetail == nil, historySessions.isEmpty {
            if let latestDailySummary {
                selectedPeriodicSummaryKind = .daily
                selectedPeriodicSummaryID = latestDailySummary.id
            } else if let latestWeeklySummary {
                selectedPeriodicSummaryKind = .weekly
                selectedPeriodicSummaryID = latestWeeklySummary.id
            }
        }
    }

    func selectedPeriodicSummary() -> StoredPeriodicSummary? {
        guard let selectedPeriodicSummaryKind else { return nil }
        return selectedPeriodicSummary(for: selectedPeriodicSummaryKind)
    }

    private func selectedPeriodicSummary(for kind: StoredPeriodicSummaryKind) -> StoredPeriodicSummary? {
        let summaries = periodicSummaryHistory(for: kind)
        guard let selectedPeriodicSummaryID else {
            return summaries.first
        }
        return summaries.first(where: { $0.id == selectedPeriodicSummaryID }) ?? summaries.first
    }

    func periodicSummaryHistory(for kind: StoredPeriodicSummaryKind) -> [StoredPeriodicSummary] {
        switch kind {
        case .daily:
            return dailySummaryHistory
        case .weekly:
            return weeklySummaryHistory
        }
    }

    private func hydrateLatestSession() {
        if let latest = store.latestSessionDetail() {
            latestSessionID = latest.session.id
            lastSessionReview = latest.review?.review
            lastSessionReviewProvider = latest.review?.providerTitle ?? ""
            lastSessionReviewPrompt = latest.review?.debugPrompt ?? ""
            lastSessionReviewRawResponse = latest.review?.debugRawResponse ?? ""
        } else {
            latestSessionID = nil
            lastSessionReview = nil
            lastSessionReviewProvider = ""
            lastSessionReviewPrompt = ""
            lastSessionReviewRawResponse = ""
        }
    }

    private func refreshReviewLearningMemory() async {
        let examples = store.validReviewFeedbackExamples(limit: 20)
        guard examples.count >= 3 else { return }
        let settings = currentCaptureSettings()
        guard reviewProviderSetupIssue(for: settings.reviewProvider) == nil else { return }

        do {
            let provider = AIProviderBridge.provider(for: settings.reviewProvider)
            let memory = try await provider.summarizeLearningMemory(
                settings: settings,
                personName: reviewDisplayName,
                feedbackExamples: examples
            )
            try store.saveReviewLearningMemory(memory)
        } catch {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: "Learning memory refresh",
                error: error.localizedDescription
            )
            assignErrorMessage(error)
        }
    }

    private func eventCount(for session: FocusSession, endingAt endAt: Date) -> Int {
        allEvents.filter { $0.occurredAt >= session.startedAt && $0.occurredAt <= endAt }.count
    }

    private func enrichSessionReview(
        _ review: SessionReview,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) -> SessionReview {
        let evidenceEvents = events.filter { !$0.kind.isFocusGuardSignal }
        let attentionSegments = AttentionDeriver.derive(from: segments)
        let evidence = makeEvidenceSummary(events: evidenceEvents)
        let timeline = !segments.isEmpty
            ? Array(segments.prefix(6)).map {
                SessionTimelineEntry(
                    at: ActivityFormatting.shortTime.string(from: $0.startAt),
                    text: [$0.primaryLabel, $0.secondaryLabel].compactMap { $0 }.joined(separator: " · "),
                    url: $0.url
                )
            }
            : (review.timeline.isEmpty ? Array(evidence.trace.prefix(6)) : Array(review.timeline.prefix(6)))

        return SessionReview(
            id: review.id,
            sessionTitle: review.sessionTitle,
            startedAt: review.startedAt,
            endedAt: review.endedAt,
            verdict: review.verdict,
            quality: review.quality,
            goalMatch: review.goalMatch,
            headline: review.headline,
            summary: review.summary,
            reviewEntities: review.reviewEntities,
            summarySpans: review.summarySpans,
            why: review.why,
            interruptions: review.interruptions,
            interruptionSpans: review.interruptionSpans,
            reasons: review.reasons,
            timeline: timeline,
            trace: evidence.trace,
            evidence: evidence,
            links: review.links.isEmpty ? makeReferenceLinks(events: evidenceEvents) : review.links,
            appDurations: appDurations(from: evidenceEvents, sessionEnd: review.endedAt),
            appSwitchCount: evidenceEvents.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count,
            repoName: TimelineDeriver.repoName(from: evidenceEvents),
            nearbyEventTitle: nil,
            mediaSummary: mediaSummary(from: evidenceEvents),
            clipboardPreview: evidence.clipboardPreviews.first,
            dominantApps: Array(segments.map(\.appName).orderedUnique().prefix(4)),
            sessionPath: Array(segments.map(\.primaryLabel).orderedUnique().prefix(4)),
            breakPointAtLabel: review.breakPointAtLabel,
            breakPoint: review.breakPoint,
            dominantThread: review.dominantThread,
            referenceURL: review.referenceURL ?? review.links.first?.url,
            focusAssessment: review.focusAssessment,
            confidenceNotes: review.confidenceNotes,
            segments: segments,
            attentionSegments: review.attentionSegments.isEmpty ? attentionSegments : review.attentionSegments
        )
    }

    private static func parseMultilineList(_ input: String) -> [String] {
        var seen: Set<String> = []
        return input
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func multilineList(from values: [String]) -> String {
        values.joined(separator: "\n")
    }

    func dismissFocusGuardPrompt() {
        activeFocusGuardPrompt = nil
    }

    func snoozeFocusGuardPrompt() {
        guard let activeSession, let prompt = activeFocusGuardPrompt else { return }
        focusGuardRuntimeState.snoozedUntil = Date().addingTimeInterval(TimeInterval(focusGuardSettings.cooldownMinutes * 60))
        nextFocusGuardEvaluationAt = focusGuardRuntimeState.snoozedUntil
        append(focusGuardEvent(kind: .focusGuardSnoozed, sessionID: activeSession.id, prompt: prompt))
        activeFocusGuardPrompt = nil
    }

    func ignoreFocusGuardPrompt() {
        guard let activeSession, let prompt = activeFocusGuardPrompt else { return }
        append(focusGuardEvent(kind: .focusGuardIgnored, sessionID: activeSession.id, prompt: prompt))
        activeFocusGuardPrompt = nil
    }

    func handleFocusGuardNotificationAction(_ action: FocusGuardNotificationCoordinator.Action, sessionID: String?) {
        guard let activeSession else { return }
        if let sessionID, sessionID != activeSession.id {
            return
        }

        switch action {
        case .backOnTrack:
            dismissFocusGuardPrompt()
        case .snooze:
            snoozeFocusGuardPrompt()
        case .ignore:
            ignoreFocusGuardPrompt()
        }
    }
}

private extension AppModel {
    struct CompletedSessionContext {
        let sessionID: String
        let title: String
        let startedAt: Date
        let endedAt: Date
        let events: [ActivityEvent]
        let segments: [TimelineSegment]
    }

    struct PeriodicSummaryWindow {
        let kind: StoredPeriodicSummaryKind
        let periodStart: Date
        let periodEnd: Date
    }

    static func timePickerDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: max(0, min(23, hour)),
            minute: max(0, min(59, minute)),
            second: 0,
            of: Date()
        ) ?? Date()
    }

    static func hourMinute(from date: Date) -> (hour: Int, minute: Int) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 21, components.minute ?? 0)
    }

    func runPendingPeriodicSummariesIfNeeded(now: Date = Date()) async {
        guard activeSession == nil, reviewInFlightSessionID == nil else { return }

        let settings = currentCaptureSettings()
        guard reviewProviderSetupIssue(for: settings.reviewProvider) == nil else { return }

        if let dailyWindow = pendingDailySummaryWindow(now: now, settings: settings.summaryAutomation) {
            await generatePeriodicSummaryIfNeeded(for: dailyWindow, settings: settings)
        }

        if let weeklyWindow = pendingWeeklySummaryWindow(now: now, settings: settings.summaryAutomation) {
            await generatePeriodicSummaryIfNeeded(for: weeklyWindow, settings: settings)
        }
    }

    func pendingDailySummaryWindow(now: Date, settings: SummaryAutomationSettings) -> PeriodicSummaryWindow? {
        guard settings.dailyEnabled else { return nil }

        let calendar = Calendar.current
        let periodStart = calendar.startOfDay(for: now)
        guard let periodEnd = calendar.date(byAdding: .day, value: 1, to: periodStart),
              let scheduledAt = calendar.date(
                bySettingHour: settings.dailyHour,
                minute: settings.dailyMinute,
                second: 0,
                of: periodStart
              ),
              now >= scheduledAt
        else {
            return nil
        }

        guard store.periodicSummary(kind: .daily, periodStart: periodStart, periodEnd: periodEnd) == nil else {
            return nil
        }

        return PeriodicSummaryWindow(kind: .daily, periodStart: periodStart, periodEnd: periodEnd)
    }

    func pendingWeeklySummaryWindow(now: Date, settings: SummaryAutomationSettings) -> PeriodicSummaryWindow? {
        guard settings.weeklyEnabled else { return nil }

        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return nil
        }

        var scheduledComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        scheduledComponents.weekday = max(1, min(7, settings.weeklyWeekday))
        scheduledComponents.hour = settings.weeklyHour
        scheduledComponents.minute = settings.weeklyMinute
        scheduledComponents.second = 0

        guard let scheduledAt = calendar.date(from: scheduledComponents), now >= scheduledAt else {
            return nil
        }

        guard store.periodicSummary(kind: .weekly, periodStart: weekInterval.start, periodEnd: weekInterval.end) == nil else {
            return nil
        }

        return PeriodicSummaryWindow(kind: .weekly, periodStart: weekInterval.start, periodEnd: weekInterval.end)
    }

    func generatePeriodicSummaryIfNeeded(for window: PeriodicSummaryWindow, settings: CaptureSettings) async {
        guard !periodicSummaryInFlightKinds.contains(window.kind) else { return }
        guard store.periodicSummary(kind: window.kind, periodStart: window.periodStart, periodEnd: window.periodEnd) == nil else { return }

        await generatePeriodicSummary(
            kind: window.kind,
            periodStart: window.periodStart,
            periodEnd: window.periodEnd,
            settings: settings,
            notifyWhenReady: settings.summaryAutomation.notifyWhenReady
        )
    }

    func regeneratePeriodicSummary(_ summary: StoredPeriodicSummary) async {
        let settings = currentCaptureSettings()
        guard reviewProviderSetupIssue(for: settings.reviewProvider) == nil else { return }
        await generatePeriodicSummary(
            kind: summary.kind,
            periodStart: summary.periodStart,
            periodEnd: summary.periodEnd,
            settings: settings,
            notifyWhenReady: false
        )
    }

    private func generatePeriodicSummary(
        kind: StoredPeriodicSummaryKind,
        periodStart: Date,
        periodEnd: Date,
        settings: CaptureSettings,
        notifyWhenReady: Bool
    ) async {
        guard !periodicSummaryInFlightKinds.contains(kind) else { return }

        let sessions = store.sessions(overlapping: periodStart, and: periodEnd)
        guard !sessions.isEmpty else { return }

        periodicSummaryInFlightKinds.insert(kind)
        defer { periodicSummaryInFlightKinds.remove(kind) }

        do {
            let provider = AIProviderBridge.provider(for: settings.reviewProvider)
            let summary = try await provider.generatePeriodicSummary(
                settings: settings,
                kind: kind,
                periodStart: periodStart,
                periodEnd: periodEnd,
                insightWritingSkill: DriftlyAgentContext.patternSkillName,
                sessions: sessions
            )
            try store.savePeriodicSummary(summary)
            refreshPeriodicSummaries()
            await sendPeriodicSummaryNotificationIfNeeded(summary, enabled: notifyWhenReady)
        } catch {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: "\(kind.displayName) refresh",
                error: error.localizedDescription
            )
        }
    }

    func sendPeriodicSummaryNotificationIfNeeded(_ summary: StoredPeriodicSummary, enabled: Bool) async {
        guard enabled else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(summary.kind.displayName) ready"
        content.body = "\(summary.title). \(summary.nextStep)"

        let request = UNNotificationRequest(
            identifier: "driftly-\(summary.kind.rawValue)-\(Int(summary.periodStart.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        await withCheckedContinuation { continuation in
            center.add(request) { _ in
                continuation.resume()
            }
        }
    }

    func evaluateFocusGuardIfNeeded(now: Date, session: FocusSession) {
        guard focusGuardPreset != .off else { return }
        guard now >= (nextFocusGuardEvaluationAt ?? session.startedAt.addingTimeInterval(focusGuardReminderInterval)) else {
            return
        }
        guard activeFocusGuardPrompt == nil else {
            nextFocusGuardEvaluationAt = now.addingTimeInterval(focusGuardReminderInterval)
            return
        }

        if let snoozedUntil = focusGuardRuntimeState.snoozedUntil, snoozedUntil > now {
            nextFocusGuardEvaluationAt = snoozedUntil
            return
        }

        guard session.endsAt.timeIntervalSince(now) > 15 else { return }

        nextFocusGuardEvaluationAt = now.addingTimeInterval(focusGuardReminderInterval)

        let prompt = FocusGuardPrompt(
            sessionID: session.id,
            message: "I hope you're focused on your work.",
            reason: "Session reminder",
            shownAt: now,
            delivery: .notification
        )

        activeFocusGuardPrompt = prompt
        focusGuardRuntimeState.lastPromptAt = now
        focusGuardRuntimeState.promptCount += 1
        append(focusGuardEvent(kind: .focusGuardPrompted, sessionID: session.id, prompt: prompt))

        Task { [focusGuardNotifications] in
            await focusGuardNotifications.schedule(prompt: prompt)
        }
    }

    private func shouldStoreDebugIO(for provider: AIReviewProvider, settings: CaptureSettings) -> Bool {
        switch provider {
        case .codex, .claude:
            return settings.chatCLI.storeDebugIO
        }
    }

    private func reviewProviderSetupIssue(for provider: AIReviewProvider) -> String? {
        switch provider {
        case .codex:
            if !codexCLIStatus.installed {
                return "Codex is not installed yet."
            }
            if !codexCLIStatus.authenticated {
                return "Codex is installed, but you still need to run `codex login`."
            }
            return nil
        case .claude:
            if !claudeCLIStatus.installed {
                return "Claude Code is not installed yet."
            }
            if !claudeCLIStatus.authenticated {
                return "Claude Code is installed, but you still need to run `claude auth login`."
            }
            return nil
        }
    }

    func currentSessionEvents(for session: FocusSession, endingAt endAt: Date) -> [ActivityEvent] {
        allEvents
            .filter { $0.occurredAt >= session.startedAt && $0.occurredAt <= endAt }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func isSessionPaused(_ events: [ActivityEvent]) -> Bool {
        guard let lastPauseEvent = events.last(where: {
            $0.kind == .userIdle || $0.kind == .userResumed || $0.kind == .systemSlept || $0.kind == .systemWoke
        }) else {
            return false
        }
        return lastPauseEvent.kind == .userIdle || lastPauseEvent.kind == .systemSlept
    }

    func focusGuardEvent(kind: ActivityKind, sessionID: String, prompt: FocusGuardPrompt) -> ActivityEvent {
        ActivityEvent(
            occurredAt: Date(),
            source: .manual,
            kind: kind,
            appName: "Driftly",
            resourceTitle: prompt.reason,
            noteText: prompt.message,
            relatedID: sessionID
        )
    }

    func resetFocusGuardState() {
        focusGuardRuntimeState = FocusGuardRuntimeState()
        nextFocusGuardEvaluationAt = nil
        focusGuardAssessment = FocusGuardAssessment.empty
        activeFocusGuardPrompt = nil
    }

    func deriveWatchRoots(from events: [ActivityEvent]) -> [String] {
        var roots: [String] = []
        var seen: Set<String> = []

        for candidate in events.reversed().flatMap({ [$0.workingDirectory, $0.path] }).compactMap({ $0 }) {
            let normalized = URL(fileURLWithPath: candidate).standardizedFileURL.path
            guard !normalized.isEmpty else { continue }
            guard !PathNoiseFilter.shouldIgnoreFileActivity(path: normalized) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            roots.append(normalized)
            if roots.count >= 12 { break }
        }
        return roots
    }

    func makeEvidenceSummary(events: [ActivityEvent]) -> SessionEvidenceSummary {
        SessionEvidenceSummary(
            topApps: topCounts(events.compactMap(\.appName), limit: 5),
            topTitles: topCounts((events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)).map(normalizedLabel(_:)), limit: 8),
            topURLs: topCounts((events.compactMap(\.resourceURL) + events.compactMap(\.domain)).map(normalizedLabel(_:)), limit: 6),
            topPaths: topCounts((events.compactMap(\.path) + events.compactMap(\.workingDirectory)).map(normalizedLabel(_:)), limit: 6),
            commands: uniquePreservingOrder(events.compactMap(\.command).map(normalizedLabel(_:)), limit: 8),
            clipboardPreviews: uniquePreservingOrder(events.compactMap(\.clipboardPreview).map(normalizedLabel(_:)), limit: 3),
            quickNotes: uniquePreservingOrder(events.compactMap(\.noteText).map(normalizedLabel(_:)), limit: 4),
            trace: makeTrace(events: events)
        )
    }

    func makeTrace(events: [ActivityEvent]) -> [SessionTimelineEntry] {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard !sorted.isEmpty else { return [] }
        var rows: [SessionTimelineEntry] = []
        var seen: Set<String> = []

        for event in sorted {
            let descriptor = TimelineDeriver.descriptor(for: event)
            let text = [descriptor.entity.primaryLabel, descriptor.entity.secondaryLabel].compactMap { $0 }.joined(separator: " · ")
            let normalized = normalizedLabel(text.isEmpty ? descriptor.appName : text)
            guard seen.insert(normalized).inserted else { continue }
            rows.append(
                SessionTimelineEntry(
                    at: ActivityFormatting.shortTime.string(from: event.occurredAt),
                    text: normalized,
                    url: descriptor.entity.url
                )
            )
        }

        return Array(rows.prefix(14))
    }

    func appDurations(from events: [ActivityEvent], sessionEnd: Date) -> [SessionAppDuration] {
        let sorted = events.sorted { $0.occurredAt < $1.occurredAt }
        guard !sorted.isEmpty else { return [] }

        var totals: [String: TimeInterval] = [:]
        for (index, event) in sorted.enumerated() {
            guard let appName = event.appName else { continue }
            let nextTime = index + 1 < sorted.count ? sorted[index + 1].occurredAt : sessionEnd
            let delta = max(0, nextTime.timeIntervalSince(event.occurredAt))
            totals[appName, default: 0] += delta
        }

        return totals
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(4)
            .map { SessionAppDuration(appName: $0.key, minutesLabel: shortDurationLabel(for: $0.value)) }
    }

    func mediaSummary(from events: [ActivityEvent]) -> String? {
        let blob = (events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle) + events.compactMap(\.resourceURL))
            .joined(separator: " ")
            .lowercased()

        if blob.contains("youtube") {
            return blob.contains("audio playing") ? "YouTube audio was active." : "YouTube was active."
        }
        if blob.contains("spotify") {
            return "Spotify was active."
        }
        return nil
    }

    func shortDurationLabel(for seconds: TimeInterval) -> String {
        let roundedMinutes = max(Int((seconds / 60).rounded()), 1)
        return "\(roundedMinutes)m"
    }

    func makeReferenceLinks(events: [ActivityEvent]) -> [SessionReferenceLink] {
        uniquePreservingOrder(events.compactMap(\.resourceURL), limit: 3).compactMap { urlString in
            guard let url = URL(string: urlString) else { return nil }
            let title = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Open link"
            return SessionReferenceLink(title: title, url: urlString)
        }
    }

    func topCounts(_ values: [String], limit: Int) -> [String] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)
    }

    func uniquePreservingOrder(_ values: [String], limit: Int) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
            if result.count >= limit { break }
        }
        return result
    }

    func normalizedLabel(_ value: String) -> String {
        let trimmed = value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 110 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 110)
        return "\(trimmed[..<index])..."
    }

}

private extension Sequence where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

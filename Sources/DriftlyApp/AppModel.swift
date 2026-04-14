import AppKit
import Combine
import Foundation
import DriftlyCore

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
    @Published var ollamaBaseURLInput = "http://127.0.0.1:11434"
    @Published var ollamaModelName = ""
    @Published var ollamaTimeoutInput = "90"
    @Published var ollamaStoreDebugIO = false
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
    @Published private(set) var availableOllamaModels: [OllamaModel] = []
    @Published private(set) var ollamaStatusMessage = ""
    @Published private(set) var ollamaStatusIsError = false
    @Published private(set) var activeSessionEventCount = 0
    @Published private(set) var historySessions: [StoredSession] = []
    @Published private(set) var selectedHistoryDetail: StoredSessionDetail?
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
    private let reviewProvider: any LocalReviewProvider = AIProviderBridge.ollama
    private let focusGuardNotifications = FocusGuardNotificationCoordinator()
    private let reviewDisplayName: String?
    private var shellImportTimer: Timer?
    private var sessionTimer: Timer?
    private var captureSettings: CaptureSettings
    private var completedSessionContext: CompletedSessionContext?
    private let memoryEventLimit = 5_000
    private var notificationObservers: [NSObjectProtocol] = []
    private let focusGuardEvaluationInterval: TimeInterval = 30
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
        self.ollamaBaseURLInput = captureSettings.ollama.baseURLString
        self.ollamaModelName = captureSettings.ollama.modelName
        self.ollamaTimeoutInput = String(captureSettings.ollama.timeoutSeconds)
        self.ollamaStoreDebugIO = captureSettings.ollama.storeDebugIO
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
        hydrateLatestSession()
        installPermissionObservers()
        start()
        Task { [weak self] in
            await self?.refreshAvailableModels()
        }
    }

    deinit {
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

    private var selectedOllamaModelName: String {
        ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var localReviewConfigured: Bool {
        let selected = selectedOllamaModelName
        guard !selected.isEmpty else { return false }
        return availableOllamaModels.contains(where: { $0.name == selected })
    }

    var hasRunningSession: Bool {
        activeSession != nil
    }

    var menuBarSymbolName: String {
        return "clock"
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

    var localReviewSetupSummary: String {
        let selected = selectedOllamaModelName

        if localReviewConfigured {
            return "Local AI review is ready with \(selected)."
        }

        if ollamaStatusIsError {
            return "AI review is not ready yet."
        }

        if !selected.isEmpty {
            return "The selected model is not installed locally."
        }

        if availableOllamaModels.isEmpty {
            return "No local model is ready for AI review yet."
        }

        return "Driftly found local models. Pick one in Settings for AI review."
    }

    var accessibilitySetupSummary: String? {
        guard trackAccessibilityTitles, !accessibilityTrusted else { return nil }
        return "Accessibility is optional, but it helps Driftly capture window titles and makes reviews more specific."
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
                actionTitle: "Enable",
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
        try? store.pruneRawEvents(olderThan: captureSettings.rawEventRetentionDays)
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
        _ = AccessibilityInspector.isTrusted(prompt: true)
        refreshPermissionStatuses()
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
        do {
            let models = try await reviewProvider.availableModels(configuration: currentOllamaConfiguration())
            availableOllamaModels = models
            ollamaStatusIsError = false

            let selectedModel = ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if models.isEmpty {
                ollamaStatusMessage = "Connected to Ollama, but no local models are installed yet."
            } else if selectedModel.isEmpty {
                ollamaStatusMessage = "Connected to Ollama. Pick one of the \(models.count) detected models for AI review."
            } else if models.contains(where: { $0.name == selectedModel }) {
                ollamaStatusMessage = "Connected to Ollama. Using \(selectedModel) for AI review."
            } else {
                ollamaStatusMessage = "Connected to Ollama, but \(selectedModel) is not installed locally."
                ollamaStatusIsError = true
            }
        } catch {
            availableOllamaModels = []
            let baseURL = currentOllamaConfiguration().baseURLString
            ollamaStatusMessage = "Couldn’t reach Ollama at \(baseURL)."
            ollamaStatusIsError = true
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
        let timeout = max(Int(ollamaTimeoutInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 90, 10)
        let retentionDays = max(Int(rawEventRetentionDaysInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30, 1)
        let resolvedFocusPreset: FocusGuardPreset = focusGuardEnabled ? .balanced : .off

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
            trackCalendarContext: false,
            fileWatchRoots: Self.parseMultilineList(fileWatchRootsInput),
            excludedAppBundleIDs: Self.parseMultilineList(excludedAppBundleIDsInput),
            excludedDomains: Self.parseMultilineList(excludedDomainsInput),
            excludedPathPrefixes: Self.parseMultilineList(excludedPathPrefixesInput),
            redactedTitleBundleIDs: Self.parseMultilineList(redactedTitleBundleIDsInput),
            droppedShellDirectoryPrefixes: Self.parseMultilineList(droppedShellDirectoryPrefixesInput),
            summaryOnlyDomains: Self.parseMultilineList(summaryOnlyDomainsInput),
            rawEventRetentionDays: retentionDays,
            ollama: OllamaConfiguration(
                baseURLString: ollamaBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines),
                modelName: ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines),
                timeoutSeconds: timeout,
                storeDebugIO: ollamaStoreDebugIO
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
            await self?.refreshAvailableModels()
        }
    }

    func setNudgesEnabled(_ enabled: Bool) {
        focusGuardEnabled = enabled
        focusGuardPreset = enabled ? .balanced : .off
    }

    private func currentOllamaConfiguration() -> OllamaConfiguration {
        let timeout = max(Int(ollamaTimeoutInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 90, 10)
        return OllamaConfiguration(
            baseURLString: ollamaBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines),
            modelName: ollamaModelName.trimmingCharacters(in: .whitespacesAndNewlines),
            timeoutSeconds: timeout,
            storeDebugIO: ollamaStoreDebugIO
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
        selectedHistoryDetail = store.sessionDetail(id: id)
    }

    func ensureHistorySelection() {
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
    }

    private func installPermissionObservers() {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatuses()
            }
        }
        notificationObservers.append(observer)
    }

    private func refreshPermissionStatuses() {
        accessibilityTrustedState = AccessibilityInspector.isTrusted(prompt: false)
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
        try? store.saveSession(pendingSession, review: nil, segments: segments, rawEventCount: sessionEvents.count)
        refreshHistory()
        performReview(for: context)
    }

    private func performReview(for context: CompletedSessionContext) {
        reviewInFlightSessionID = context.sessionID
        guard !context.events.isEmpty else {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: context.title,
                error: "Not enough captured evidence to ask Ollama for a review."
            )
            applyReviewFailure(
                sessionID: context.sessionID,
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                segments: context.segments,
                rawEventCount: context.events.count,
                reviewStatus: .failed,
                message: "Not enough captured evidence to ask Ollama for a review."
            )
            return
        }

        guard !captureSettings.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: context.title,
                error: "No Ollama model is selected for review generation."
            )
            applyReviewFailure(
                sessionID: context.sessionID,
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                segments: context.segments,
                rawEventCount: context.events.count,
                reviewStatus: .unavailable,
                message: "No Ollama model is selected for review generation."
            )
            return
        }

        Task {
            do {
                let run = try await reviewProvider.generateReview(
                    configuration: captureSettings.ollama,
                    title: context.title,
                    personName: reviewDisplayName,
                    contextPattern: store.contextPatternSnapshot(goal: context.title, excludingSessionID: context.sessionID),
                    reviewLearnings: store.reviewLearningMemory()?.learnings ?? [],
                    feedbackExamples: store.promptReadyReviewFeedbackExamples(),
                    startedAt: context.startedAt,
                    endedAt: context.endedAt,
                    events: context.events,
                    segments: context.segments
                )
                applyCompletedReview(
                    enrichSessionReview(run.review, events: context.events, segments: context.segments),
                    sessionID: context.sessionID,
                    providerTitle: run.providerTitle,
                    prompt: captureSettings.ollama.storeDebugIO ? run.prompt : "",
                    rawResponse: captureSettings.ollama.storeDebugIO ? run.rawResponse : "",
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
                    message: "AI generation failed.",
                    prompt: captureSettings.ollama.storeDebugIO ? "Review prompt failed." : "",
                    rawResponse: captureSettings.ollama.storeDebugIO ? error.localizedDescription : ""
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
            hydrateLatestSession()
            lastReviewErrorMessage = reviewStatus == .ready ? nil : lastReviewErrorMessage
            errorMessage = nil
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
        guard !captureSettings.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            let memory = try await reviewProvider.summarizeLearningMemory(
                configuration: captureSettings.ollama,
                personName: reviewDisplayName,
                feedbackExamples: examples
            )
            try store.saveReviewLearningMemory(memory)
        } catch {
            // Keep prior learning memory on failure.
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
            summarySpans: review.summarySpans,
            why: review.why,
            interruptions: review.interruptions,
            interruptionSpans: review.interruptionSpans,
            reasons: review.reasons,
            timeline: timeline,
            trace: evidence.trace,
            evidence: evidence,
            links: makeReferenceLinks(events: evidenceEvents),
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
            referenceURL: review.referenceURL,
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

    func evaluateFocusGuardIfNeeded(now: Date, session: FocusSession) {
        guard now >= (nextFocusGuardEvaluationAt ?? session.startedAt) else { return }
        nextFocusGuardEvaluationAt = now.addingTimeInterval(focusGuardEvaluationInterval)

        let sessionEvents = currentSessionEvents(for: session, endingAt: now)
        let decision = FocusGuardEvaluator.evaluate(
            goal: session.title,
            session: session,
            events: sessionEvents,
            settings: focusGuardSettings,
            state: focusGuardRuntimeState,
            now: now,
            isUserIdle: isSessionPaused(sessionEvents)
        )

        focusGuardRuntimeState = decision.state
        focusGuardAssessment = decision.assessment

        if decision.recordedRecovery {
            append(
                ActivityEvent(
                    occurredAt: now,
                    source: .manual,
                    kind: .focusGuardRecovered,
                    appName: "Driftly",
                    resourceTitle: decision.assessment.reason,
                    relatedID: session.id
                )
            )
            activeFocusGuardPrompt = nil
        }

        guard decision.shouldPrompt,
              let promptMessage = decision.promptMessage,
              let promptReason = decision.promptReason else {
            return
        }

        let delivery: FocusGuardPromptDelivery = .notification
        let fallbackMessage = promptMessage
        let assessment = decision.assessment
        let currentEvents = sessionEvents

        Task { [weak self, focusGuardNotifications] in
            guard let self else { return }

            let generatedMessage: String
            if !self.captureSettings.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do {
                    generatedMessage = try await self.reviewProvider.generateFocusGuardNudge(
                        configuration: self.captureSettings.ollama,
                        goal: session.title,
                        assessmentReason: promptReason,
                        driftLabels: assessment.driftLabels,
                        matchedLabels: assessment.matchedLabels,
                        events: currentEvents
                    )
                } catch {
                    generatedMessage = fallbackMessage
                }
            } else {
                generatedMessage = fallbackMessage
            }

            await MainActor.run {
                guard self.activeSession?.id == session.id else { return }
                let prompt = FocusGuardPrompt(
                    sessionID: session.id,
                    message: generatedMessage,
                    reason: promptReason,
                    shownAt: now,
                    delivery: delivery
                )
                self.activeFocusGuardPrompt = prompt
                self.append(self.focusGuardEvent(kind: .focusGuardPrompted, sessionID: session.id, prompt: prompt))
                Task { [focusGuardNotifications] in
                    await focusGuardNotifications.schedule(prompt: prompt)
                }
            }
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

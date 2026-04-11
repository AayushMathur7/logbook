import AppKit
import Combine
import EventKit
import Foundation
import LogbookCore

enum SessionScreenState: String, Equatable {
    case setup
    case running
    case generatingReview
    case reviewReady
}

enum PermissionOnboardingKind: String, Identifiable {
    case accessibility
    case calendar

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
    @Published var trackCalendarContext = true
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
    @Published private(set) var calendarAuthorizationStatus: EKAuthorizationStatus
    @Published private(set) var calendarEvents: [CalendarEventSummary] = []
    @Published private(set) var availableOllamaModels: [OllamaModel] = []
    @Published private(set) var ollamaStatusMessage = ""
    @Published private(set) var ollamaStatusIsError = false
    @Published private(set) var activeSessionEventCount = 0
    @Published private(set) var historySessions: [StoredSession] = []
    @Published private(set) var selectedHistoryDetail: StoredSessionDetail?
    @Published private(set) var reviewInFlightSessionID: String?
    @Published var showPermissionOnboarding = true

    private let monitor = ActivityMonitor()
    private let fileMonitor = FileActivityMonitor()
    private let eventStore = EKEventStore()
    private let store = SessionStore()
    private let reviewProvider: any LocalReviewProvider = AIProviderBridge.ollama
    private let reviewDisplayName: String?
    private var shellImportTimer: Timer?
    private var sessionTimer: Timer?
    private var captureSettings: CaptureSettings
    private var completedSessionContext: CompletedSessionContext?
    private let memoryEventLimit = 5_000
    private var notificationObservers: [NSObjectProtocol] = []

    init() {
        self.captureSettings = store.loadCaptureSettings()
        self.allEvents = store.recentEvents()
        self.accessibilityTrustedState = AccessibilityInspector.isTrusted(prompt: false)
        self.calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
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

        monitor.onEvent = { [weak self] event in
            self?.append(event)
        }
        fileMonitor.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.append(event)
            }
        }

        refreshCalendarEventsIfAuthorized()
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

    var sessionGoalIsValid: Bool {
        !sessionDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var calendarAccessDescription: String {
        guard trackCalendarContext else {
            return "Calendar context is off for reviews."
        }

        switch calendarAuthorizationStatus {
        case .notDetermined:
            return "Calendar access is off. Enable it if you want nearby meetings in session evidence."
        case .restricted, .denied:
            return "Calendar access is denied. Enable it in System Settings to include nearby events."
        case .authorized, .fullAccess:
            return "Nearby calendar events can be included in reviews."
        case .writeOnly:
            return "Calendar access is write-only. Log Book needs read access for context."
        @unknown default:
            return "Calendar status is unknown."
        }
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

        let calendarItem: PermissionOnboardingItem = {
            guard trackCalendarContext else {
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Disabled in Settings",
                    detail: "Calendar context is off, so meetings will not appear in session evidence.",
                    actionTitle: "Open settings",
                    isSatisfied: true
                )
            }

            switch calendarAuthorizationStatus {
            case .authorized, .fullAccess:
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Enabled",
                    detail: "Nearby meetings can be used as lightweight session context.",
                    actionTitle: "Review",
                    isSatisfied: true
                )
            case .notDetermined:
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Optional",
                    detail: "Grant read access if you want nearby meetings included in reviews.",
                    actionTitle: "Allow",
                    isSatisfied: false
                )
            case .restricted, .denied:
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Denied",
                    detail: "Calendar access was denied. You can still use Log Book; this only removes meeting context.",
                    actionTitle: "Open settings",
                    isSatisfied: false
                )
            case .writeOnly:
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Needs read access",
                    detail: "Log Book needs read access to include nearby events in the session review.",
                    actionTitle: "Open settings",
                    isSatisfied: false
                )
            @unknown default:
                return PermissionOnboardingItem(
                    kind: .calendar,
                    title: "Calendar",
                    status: "Unknown",
                    detail: "Calendar status could not be determined. The app still works without it.",
                    actionTitle: "Review",
                    isSatisfied: false
                )
            }
        }()

        return [accessibilityItem, calendarItem]
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

        return "\(missing.count) permissions are still missing. Log Book will work, but the review will be less detailed."
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
        if trackCalendarContext { labels.append("calendar") }
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
                appName: "Log Book"
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

    func requestCalendarAccess() {
        guard trackCalendarContext else { return }

        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshPermissionStatuses()
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.refreshPermissionStatuses()
                }
            }
        }
    }

    func performPermissionOnboardingAction(for kind: PermissionOnboardingKind) {
        switch kind {
        case .accessibility:
            if trackAccessibilityTitles, !accessibilityTrusted {
                requestAccessibilityAccess()
            } else {
                hidePermissionOnboarding()
            }
        case .calendar:
            switch calendarAuthorizationStatus {
            case .notDetermined:
                requestCalendarAccess()
            case .restricted, .denied, .writeOnly:
                openSystemSettingsPrivacyPane(anchor: "Privacy_Calendars")
            case .authorized, .fullAccess:
                hidePermissionOnboarding()
            @unknown default:
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
                ollamaStatusMessage = "Connected to Ollama, but no local models are installed."
            } else if selectedModel.isEmpty {
                ollamaStatusMessage = "Connected to Ollama. Select one of the \(models.count) detected models."
            } else if models.contains(where: { $0.name == selectedModel }) {
                ollamaStatusMessage = "Connected to Ollama. Using \(selectedModel)."
            } else {
                ollamaStatusMessage = "Connected to Ollama, but \(selectedModel) is not installed locally."
                ollamaStatusIsError = true
            }
        } catch {
            availableOllamaModels = []
            ollamaStatusMessage = error.localizedDescription
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
        startSessionTimer()
    }

    func endSessionNow() {
        finishSession(endedAt: Date())
    }

    func startNextSession() {
        surfaceState = .setup
        quickNoteInput = ""
        lastReviewErrorMessage = nil
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
        let calendarTitles = nearbyCalendarTitles(startedAt: detail.session.startedAt, endedAt: detail.session.endedAt)
        let context = CompletedSessionContext(
            sessionID: detail.session.id,
            title: detail.session.goal,
            startedAt: detail.session.startedAt,
            endedAt: detail.session.endedAt,
            events: events,
            calendarTitles: calendarTitles,
            segments: detail.segments
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
                appName: "Log Book",
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
            errorMessage = error.localizedDescription
        }
    }

    func clearModelDebugData() {
        do {
            try store.clearModelDebugData()
            refreshHistory()
            hydrateLatestSession()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func saveCaptureSettings() {
        let timeout = max(Int(ollamaTimeoutInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 90, 10)
        let retentionDays = max(Int(rawEventRetentionDaysInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 30, 1)

        captureSettings = CaptureSettings(
            trackAccessibilityTitles: trackAccessibilityTitles,
            trackBrowserContext: trackBrowserContext,
            trackFinderContext: trackFinderContext,
            trackShellCommands: trackShellCommands,
            trackFileSystemActivity: trackFileSystemActivity,
            trackClipboard: trackClipboard,
            trackPresence: trackPresence,
            trackCalendarContext: trackCalendarContext,
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
            errorMessage = error.localizedDescription
        }

        refreshFileMonitorRoots()
        refreshCalendarEventsIfAuthorized()
        Task { [weak self] in
            await self?.refreshAvailableModels()
        }
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

    func restorePrimarySessionSurface(preferred state: SessionScreenState? = nil) {
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
                surfaceState = lastSessionReview == nil ? .setup : .reviewReady
                return
            case .running:
                surfaceState = .setup
                return
            case .generatingReview:
                hydrateLatestSession()
                surfaceState = lastSessionReview == nil ? .setup : .reviewReady
                return
            }
        }

        hydrateLatestSession()
        surfaceState = lastSessionReview == nil ? .setup : .reviewReady
    }

    private func applyCaptureSettings(_ settings: CaptureSettings) {
        captureEnabled = true
        trackAccessibilityTitles = settings.trackAccessibilityTitles
        trackBrowserContext = settings.trackBrowserContext
        trackFinderContext = settings.trackFinderContext
        trackShellCommands = settings.trackShellCommands
        trackFileSystemActivity = settings.trackFileSystemActivity
        trackClipboard = settings.trackClipboard
        trackPresence = settings.trackPresence
        trackCalendarContext = settings.trackCalendarContext
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
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refreshCalendarEventsIfAuthorized()
    }

    private func openSystemSettingsPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
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
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCalendarEventsIfAuthorized() {
        guard hasCalendarAccess, trackCalendarContext else {
            calendarEvents = []
            return
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        calendarEvents = eventStore.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map {
                CalendarEventSummary(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title?.isEmpty == false ? $0.title! : "Untitled Event",
                    calendarTitle: $0.calendar.title,
                    startAt: $0.startDate,
                    endAt: $0.endDate
                )
            }
    }

    private var hasCalendarAccess: Bool {
        if #available(macOS 14.0, *) {
            return calendarAuthorizationStatus == .fullAccess || calendarAuthorizationStatus == .authorized
        }
        return calendarAuthorizationStatus == .authorized
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
        surfaceState = .generatingReview

        let sessionEvents = store.events(between: activeSession.startedAt, and: endedAt)
        let calendarTitles = nearbyCalendarTitles(startedAt: activeSession.startedAt, endedAt: endedAt)
        let segments = TimelineDeriver.deriveSegments(from: sessionEvents, sessionEnd: endedAt)
        let context = CompletedSessionContext(
            sessionID: activeSession.id,
            title: activeSession.title,
            startedAt: activeSession.startedAt,
            endedAt: endedAt,
            events: sessionEvents,
            calendarTitles: calendarTitles,
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
            lastReviewErrorMessage = "Not enough captured evidence to ask Ollama for a review."
            let fallback = fallbackReview(
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                events: context.events,
                calendarTitles: context.calendarTitles,
                segments: context.segments,
                headline: "No usable evidence for this block.",
                summary: "The session ended before Log Book captured enough evidence to build a grounded timeline."
            )
            applyCompletedReview(
                fallback,
                sessionID: context.sessionID,
                providerTitle: "Local fallback",
                prompt: "",
                rawResponse: "",
                reviewStatus: .failed,
                rawEventCount: context.events.count
            )
            return
        }

        guard !captureSettings.ollama.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastReviewErrorMessage = "No Ollama model is selected in Settings. Showing the local fallback review."
            let fallback = fallbackReview(
                title: context.title,
                startedAt: context.startedAt,
                endedAt: context.endedAt,
                events: context.events,
                calendarTitles: context.calendarTitles,
                segments: context.segments,
                headline: "Timeline saved. No local model selected.",
                summary: "Log Book captured the block and built the timeline, but no Ollama model is configured for an AI review."
            )
            applyCompletedReview(
                fallback,
                sessionID: context.sessionID,
                providerTitle: "Local fallback",
                prompt: "",
                rawResponse: "",
                reviewStatus: .unavailable,
                rawEventCount: context.events.count
            )
            return
        }

        Task {
            do {
                let run = try await reviewProvider.generateReview(
                    configuration: captureSettings.ollama,
                    title: context.title,
                    personName: reviewDisplayName,
                    startedAt: context.startedAt,
                    endedAt: context.endedAt,
                    events: context.events,
                    segments: context.segments,
                    calendarTitles: context.calendarTitles
                )
                let enriched = enrichSessionReview(run.review, events: context.events, calendarTitles: context.calendarTitles, segments: context.segments)
                applyCompletedReview(
                    enriched,
                    sessionID: context.sessionID,
                    providerTitle: run.providerTitle,
                    prompt: captureSettings.ollama.storeDebugIO ? run.prompt : "",
                    rawResponse: captureSettings.ollama.storeDebugIO ? run.rawResponse : "",
                    reviewStatus: .ready,
                    rawEventCount: context.events.count
                )
            } catch {
                let fallback = fallbackReview(
                    title: context.title,
                    startedAt: context.startedAt,
                    endedAt: context.endedAt,
                    events: context.events,
                    calendarTitles: context.calendarTitles,
                    segments: context.segments,
                    headline: "Timeline saved. Local review failed.",
                    summary: "The local model response could not be parsed cleanly, so this recap was rebuilt from the captured timeline."
                )
                applyCompletedReview(
                    fallback,
                    sessionID: context.sessionID,
                    providerTitle: "Ollama",
                    prompt: captureSettings.ollama.storeDebugIO ? "Review prompt failed." : "",
                    rawResponse: captureSettings.ollama.storeDebugIO ? error.localizedDescription : "",
                    reviewStatus: .failed,
                    rawEventCount: context.events.count
                )
                lastReviewErrorMessage = error.localizedDescription
            }
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
            errorMessage = error.localizedDescription
        }
    }

    private func fallbackReview(
        title: String,
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        calendarTitles: [String],
        segments: [TimelineSegment],
        headline _: String,
        summary fallbackSummary: String
    ) -> SessionReview {
        let narrative = makeLocalNarrative(
            title: title,
            startedAt: startedAt,
            endedAt: endedAt,
            segments: segments,
            fallbackSummary: fallbackSummary
        )

        return enrichSessionReview(
            SessionReview(
                sessionTitle: title,
                startedAt: startedAt,
                endedAt: endedAt,
                verdict: narrative.verdict,
                quality: narrative.quality,
                goalMatch: narrative.goalMatch,
                headline: narrative.headline,
                summary: narrative.summary,
                summarySpans: [],
                why: narrative.summary,
                interruptions: narrative.interruptions,
                interruptionSpans: [],
                reasons: narrative.reasons,
                timeline: [],
                trace: [],
                focusAssessment: narrative.focusAssessment,
                confidenceNotes: narrative.confidenceNotes,
                segments: segments
            ),
            events: events,
            calendarTitles: calendarTitles,
            segments: segments
        )
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
            lastSessionReview = latest.review?.review
            lastSessionReviewProvider = latest.review?.providerTitle ?? ""
            lastSessionReviewPrompt = latest.review?.debugPrompt ?? ""
            lastSessionReviewRawResponse = latest.review?.debugRawResponse ?? ""
        } else {
            lastSessionReview = nil
            lastSessionReviewProvider = ""
            lastSessionReviewPrompt = ""
            lastSessionReviewRawResponse = ""
        }
    }

    private func eventCount(for session: FocusSession, endingAt endAt: Date) -> Int {
        allEvents.filter { $0.occurredAt >= session.startedAt && $0.occurredAt <= endAt }.count
    }

    private func nearbyCalendarTitles(startedAt: Date, endedAt: Date) -> [String] {
        guard trackCalendarContext else { return [] }
        let paddedStart = startedAt.addingTimeInterval(-15 * 60)
        let paddedEnd = endedAt.addingTimeInterval(15 * 60)
        return calendarEvents
            .filter { $0.endAt >= paddedStart && $0.startAt <= paddedEnd }
            .map(\.title)
    }

    private func enrichSessionReview(
        _ review: SessionReview,
        events: [ActivityEvent],
        calendarTitles: [String],
        segments: [TimelineSegment]
    ) -> SessionReview {
        let attentionSegments = AttentionDeriver.derive(from: segments)
        let evidence = makeEvidenceSummary(events: events, calendarTitles: calendarTitles)
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
            why: review.summary,
            interruptions: review.interruptions,
            interruptionSpans: review.interruptionSpans,
            reasons: review.reasons.isEmpty ? review.confidenceNotes : review.reasons,
            timeline: timeline,
            trace: evidence.trace,
            evidence: evidence,
            links: makeReferenceLinks(events: events),
            appDurations: appDurations(from: events, sessionEnd: review.endedAt),
            appSwitchCount: events.filter { $0.kind == .appActivated || $0.kind == .tabChanged }.count,
            repoName: TimelineDeriver.repoName(from: events),
            nearbyEventTitle: calendarTitles.first,
            mediaSummary: mediaSummary(from: events),
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
}

private extension AppModel {
    struct LocalNarrative {
        let headline: String
        let summary: String
        let focusAssessment: String
        let interruptions: [String]
        let reasons: [String]
        let confidenceNotes: [String]
        let verdict: SessionVerdict
        let quality: SessionQuality
        let goalMatch: SessionGoalMatch
    }

    struct CompletedSessionContext {
        let sessionID: String
        let title: String
        let startedAt: Date
        let endedAt: Date
        let events: [ActivityEvent]
        let calendarTitles: [String]
        let segments: [TimelineSegment]
    }

    enum LocalSegmentRole {
        case work
        case drift
        case neutral
    }

    struct NarrativePhrase {
        let clause: String
        let duration: TimeInterval
        let richness: Int
    }

    struct WorkContext {
        let file: String?
        let repo: String?
    }

    func makeLocalNarrative(
        title: String,
        startedAt: Date,
        endedAt: Date,
        segments: [TimelineSegment],
        fallbackSummary: String
    ) -> LocalNarrative {
        let attentionSegments = AttentionDeriver.derive(from: segments)
        let narrativeSegments = attentionSegments.map(\.foreground)
        let overlays = attentionSegments.flatMap(\.overlays)
        let intent = TimelineDeriver.deriveIntent(from: title)

        guard !narrativeSegments.isEmpty else {
            let summary = "There wasn’t enough captured activity in this session window to say what you were doing."
            return LocalNarrative(
                headline: "This block didn’t leave much usable evidence.",
                summary: summary,
                focusAssessment: summary,
                interruptions: [],
                reasons: [],
                confidenceNotes: [fallbackSummary, "This review was generated locally from the captured session timeline."],
                verdict: .partiallyMatched,
                quality: .mixed,
                goalMatch: .unclear
            )
        }

        let totalDuration = max(narrativeSegments.reduce(0) { $0 + segmentDuration($1) }, 1)
        let observedSegments = TimelineDeriver.observeSegments(narrativeSegments, goal: title)
        let observedRoles = Dictionary(uniqueKeysWithValues: observedSegments.map { ($0.segment.id, $0.role) })
        let observability = TimelineDeriver.summarizeObservedSegments(observedSegments)
        let alignedSegments = narrativeSegments.filter {
            switch observedRoles[$0.id] {
            case .direct?, .support?:
                return true
            default:
                return false
            }
        }
        let driftSegments = narrativeSegments.filter { observedRoles[$0.id] == .drift }
        let alignedDuration = TimeInterval(observability.directSeconds + observability.supportSeconds)
        let driftDuration = TimeInterval(observability.driftSeconds)
        let switchCount = max(narrativeSegments.count - 1, 0)

        let goalMatch: SessionGoalMatch
        let quality: SessionQuality
        switch observability.goalProgressEstimate {
        case .strong:
            goalMatch = .strong
            quality = .coherent
        case .partial:
            goalMatch = .partial
            quality = driftDuration >= totalDuration * 0.35 || switchCount >= 8 ? .mixed : .coherent
        case .weak:
            goalMatch = alignedDuration >= totalDuration * 0.25 ? .partial : .weak
            quality = .mixed
        case .none:
            goalMatch = .weak
            quality = .drifted
        }

        let verdict = SessionVerdict(goalMatch: goalMatch)
        let dominantContext = dominantWorkContext(in: narrativeSegments)
        let workPhrases = selectedPhrases(from: alignedSegments, role: .work, dominantContext: dominantContext, limit: 3)
        let driftPhrases = selectedPhrases(from: driftSegments, role: .drift, dominantContext: dominantContext, limit: 3)
        let breakCount = narrativeSegments.filter(isBreakSegment(_:)).count

        let headline: String
        switch verdict {
        case .matched:
            headline = "You mostly stayed with the work in this block."
        case .partiallyMatched:
            headline = driftDuration > alignedDuration
                ? "You stayed near the work, but the block kept drifting."
                : "You made progress, but the block stayed fragmented."
        case .missed:
            headline = "You circled the work more than you pushed it forward."
        }

        let summary = conciseNarrativeSummary(
            title: title,
            intent: intent,
            verdict: verdict,
            workPhrases: workPhrases,
            driftPhrases: driftPhrases,
            firstNeutralSegment: narrativeSegments.first,
            dominantContext: dominantContext,
            audioOverlay: overlays.first(where: { $0.kind == .audio })
        )

        let focusAssessment: String
        switch verdict {
        case .matched:
            focusAssessment = "The clearest signal was \(joinClauses(Array(workPhrases.prefix(2)))). Drift stayed limited inside this session."
        case .partiallyMatched:
            if !workPhrases.isEmpty && !driftPhrases.isEmpty {
                focusAssessment = "The strongest work signal was \(joinClauses(Array(workPhrases.prefix(2)))), but \(joinClauses(Array(driftPhrases.prefix(2)))) kept interrupting the block."
            } else {
                focusAssessment = "This block mixed real work with enough drift that the session never fully locked in."
            }
        case .missed:
            if !driftPhrases.isEmpty {
                if isIntentProgressSession(intent) {
                    focusAssessment = "Most of the session was absorbed by \(joinClauses(Array(driftPhrases.prefix(2)))) rather than direct progress on \(inlineEmphasis(title))."
                } else {
                    focusAssessment = "Most of the session moved through \(joinClauses(Array(driftPhrases.prefix(2)))) instead of staying with the session intent."
                }
            } else {
                focusAssessment = "This session did not leave a strong enough work thread to call it focused."
            }
        }

        let interruptions = interruptionSummaries(from: driftSegments, breakCount: breakCount, overlays: overlays)
        var confidenceNotes = [fallbackSummary, "This review was generated locally from the captured session timeline."]
        if !overlays.isEmpty {
            confidenceNotes.append("Background context can overlap foreground activity, so attention is inferred rather than observed directly.")
        }
        return LocalNarrative(
            headline: headline,
            summary: summary,
            focusAssessment: focusAssessment,
            interruptions: interruptions,
            reasons: [],
            confidenceNotes: confidenceNotes,
            verdict: verdict,
            quality: quality,
            goalMatch: goalMatch
        )
    }

    func deriveWatchRoots(from events: [ActivityEvent]) -> [String] {
        var roots: [String] = []
        var seen: Set<String> = []

        for candidate in events.reversed().flatMap({ [$0.workingDirectory, $0.path] }).compactMap({ $0 }) {
            let normalized = URL(fileURLWithPath: candidate).standardizedFileURL.path
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            roots.append(normalized)
            if roots.count >= 12 { break }
        }
        return roots
    }

    func makeEvidenceSummary(events: [ActivityEvent], calendarTitles: [String]) -> SessionEvidenceSummary {
        SessionEvidenceSummary(
            topApps: topCounts(events.compactMap(\.appName), limit: 5),
            topTitles: topCounts((events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)).map(normalizedLabel(_:)), limit: 8),
            topURLs: topCounts((events.compactMap(\.resourceURL) + events.compactMap(\.domain)).map(normalizedLabel(_:)), limit: 6),
            topPaths: topCounts((events.compactMap(\.path) + events.compactMap(\.workingDirectory)).map(normalizedLabel(_:)), limit: 6),
            commands: uniquePreservingOrder(events.compactMap(\.command).map(normalizedLabel(_:)), limit: 8),
            clipboardPreviews: uniquePreservingOrder(events.compactMap(\.clipboardPreview).map(normalizedLabel(_:)), limit: 3),
            quickNotes: uniquePreservingOrder(events.compactMap(\.noteText).map(normalizedLabel(_:)), limit: 4),
            calendarTitles: calendarTitles,
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

    func localRole(for observedRole: SessionSegmentRole) -> LocalSegmentRole {
        switch observedRole {
        case .direct, .support:
            return .work
        case .drift, .breakTime:
            return .drift
        case .neutral:
            return .neutral
        }
    }

    func isBreakSegment(_ segment: TimelineSegment) -> Bool {
        segment.appName == "Log Book" && segment.primaryLabel.lowercased().contains("break")
    }

    func selectedPhrases(from segments: [TimelineSegment], role: LocalSegmentRole, dominantContext: WorkContext?, limit: Int) -> [String] {
        let candidates = segments.compactMap { segment -> NarrativePhrase? in
            guard let clause = activityClause(for: segment, role: role, dominantContext: dominantContext) else { return nil }
            return NarrativePhrase(clause: clause, duration: segmentDuration(segment), richness: phraseRichness(for: segment))
        }

        let richThreshold = role == .work ? 2 : 1
        let preferred = candidates.filter { $0.richness >= richThreshold }
        let source = preferred.isEmpty ? candidates : preferred

        var seen: Set<String> = []
        var result: [String] = []
        for candidate in source {
            if seen.insert(candidate.clause).inserted {
                result.append(candidate.clause)
            }
            if result.count >= limit { break }
        }
        return result
    }

    func activityClause(for segment: TimelineSegment, role: LocalSegmentRole, dominantContext: WorkContext?) -> String? {
        let primary = normalizedLabel(segment.primaryLabel)
        let secondary = segment.secondaryLabel.map(normalizedLabel(_:))
        let lowerPrimary = primary.lowercased()
        let lowerApp = segment.appName.lowercased()
        let domain = (segment.domain ?? "").lowercased()
        let fileName = segment.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }

        if isBreakSegment(segment) {
            return "taking a short break"
        }

        if lowerPrimary.contains("new tab") {
            return "sitting in \(inlineEmphasis("New tab"))"
        }

        if domain == "github.com" {
            if let secondary, secondary.contains("/") {
                return "reviewing \(inlineCode(secondary)) on \(inlineEmphasis("GitHub"))"
            }
            return "browsing \(inlineEmphasis("GitHub"))"
        }

        if domain.contains("calendar.notion.so") || lowerPrimary.contains("calendar") {
            return "checking \(inlineEmphasis("Notion Calendar"))"
        }

        if domain == "youtube.com" || domain == "youtu.be" {
            if primary == "YouTube Home" {
                return role == .drift ? "drifting into \(inlineEmphasis("YouTube Home"))" : "opening \(inlineEmphasis("YouTube Home"))"
            }
            if primary == "YouTube Shorts", let secondary, !secondary.isEmpty {
                return "viewing \(inlineEmphasis(secondary)) in \(inlineEmphasis("YouTube Shorts"))"
            }
            if primary == "YouTube Watch", let secondary, !secondary.isEmpty {
                return "viewing \(inlineEmphasis(secondary)) on \(inlineEmphasis("YouTube"))"
            }
            if let secondary, !secondary.isEmpty {
                return "opening \(inlineEmphasis(secondary)) on \(inlineEmphasis("YouTube"))"
            }
            return "opening \(inlineEmphasis("YouTube"))"
        }

        if domain == "x.com" || domain == "twitter.com" {
            if secondary == "Home feed" {
                return "checking the \(inlineEmphasis("X")) home feed"
            }
            if let secondary, !secondary.isEmpty {
                return "opening \(inlineEmphasis(secondary)) on \(inlineEmphasis("X"))"
            }
            return "opening \(inlineEmphasis("X"))"
        }

        if lowerApp.contains("spotify") {
            return primary.lowercased() == "spotify"
                ? "switching to \(inlineEmphasis("Spotify"))"
                : "switching to \(inlineEmphasis("Spotify")) with \(inlineEmphasis(primary)) visible"
        }

        if let repoName = segment.repoName, let fileName, fileName != segment.appName {
            return "editing \(inlineCode(fileName)) in \(inlineCode(repoName))"
        }

        if let fileName, fileName != segment.appName {
            return "editing \(inlineCode(fileName))"
        }

        if let repoName = segment.repoName, let secondary, !secondary.isEmpty, secondary != repoName {
            if role == .work {
                return "reviewing \(inlineCode(secondary))"
            }
            return "looking at \(inlineCode(secondary))"
        }

        if let repoName = segment.repoName, !repoName.isEmpty {
            return role == .work ? "working in \(inlineCode(repoName))" : "looking around \(inlineCode(repoName))"
        }

        if lowerApp.contains("cursor") || lowerApp.contains("codex") || lowerApp.contains("xcode") || lowerApp.contains("code") {
            if let file = dominantContext?.file, let repo = dominantContext?.repo {
                return "editing \(inlineCode(file)) in \(inlineCode(repo))"
            }
            if let file = dominantContext?.file {
                return "editing \(inlineCode(file))"
            }
            if let repo = dominantContext?.repo {
                return "working in \(inlineCode(repo))"
            }
            return "working in \(inlineCode(segment.appName))"
        }

        if primary != segment.appName {
            switch role {
            case .work:
                return "working on \(inlineEmphasis(primary))"
            case .drift:
                return "opening \(inlineEmphasis(primary))"
            case .neutral:
                return "moving through \(inlineEmphasis(primary))"
            }
        }

        return role == .work ? "working in \(inlineEmphasis(segment.appName))" : "switching into \(inlineEmphasis(segment.appName))"
    }

    func dominantWorkContext(in segments: [TimelineSegment]) -> WorkContext? {
        let workSegments = segments.filter {
            $0.category == .coding || $0.filePath != nil || $0.repoName != nil || ($0.domain ?? "") == "github.com"
        }

        let file = workSegments
            .compactMap(\.filePath)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            .first(where: { !$0.isEmpty })
        let repo = workSegments
            .compactMap(\.repoName)
            .first(where: { !$0.isEmpty })

        guard file != nil || repo != nil else { return nil }
        return WorkContext(file: file, repo: repo)
    }

    func phraseRichness(for segment: TimelineSegment) -> Int {
        if isBreakSegment(segment) { return 2 }
        if segment.filePath != nil { return 3 }
        if segment.repoName != nil { return 3 }
        if let domain = segment.domain, ["github.com", "youtube.com", "youtu.be", "x.com", "twitter.com"].contains(domain) {
            return 3
        }
        if segment.primaryLabel.lowercased().contains("new tab") {
            return 1
        }
        return segment.secondaryLabel == nil ? 1 : 2
    }

    func segmentDuration(_ segment: TimelineSegment) -> TimeInterval {
        max(segment.endAt.timeIntervalSince(segment.startAt), 0)
    }

    func joinClauses(_ clauses: [String]) -> String {
        switch clauses.count {
        case 0:
            return ""
        case 1:
            return clauses[0]
        case 2:
            return "\(clauses[0]) and \(clauses[1])"
        default:
            let head = clauses.dropLast().joined(separator: ", ")
            return "\(head), and \(clauses.last!)"
        }
    }

    func interruptionSummaries(from driftSegments: [TimelineSegment], breakCount: Int, overlays: [AttentionOverlay]) -> [String] {
        var items: [String] = []

        let newTabSeconds = driftSegments
            .filter { $0.primaryLabel.lowercased().contains("new tab") }
            .reduce(0) { $0 + segmentDuration($1) }
        if newTabSeconds >= 45 {
            items.append("\(inlineEmphasis("New tab")) absorbed a noticeable part of the block.")
        }

        if driftSegments.contains(where: { ($0.domain ?? "").contains("calendar.notion.so") || $0.primaryLabel.lowercased().contains("calendar") }) {
            items.append("You checked \(inlineEmphasis("Notion Calendar")) during the session.")
        }

        if let youtube = driftSegments.first(where: { ($0.domain ?? "") == "youtube.com" || ($0.domain ?? "") == "youtu.be" }) {
            if youtube.primaryLabel == "YouTube Home" {
                items.append("You drifted into \(inlineEmphasis("YouTube Home")) during the block.")
            } else if let secondary = youtube.secondaryLabel, !secondary.isEmpty {
                items.append("You opened \(inlineEmphasis(secondary)) on \(inlineEmphasis("YouTube")) during the block.")
            } else {
                items.append("You opened \(inlineEmphasis("YouTube")) during the block.")
            }
        }

        if let spotify = overlays.first(where: { $0.kind == .audio && $0.segment.appName.lowercased().contains("spotify") })?.segment {
            if spotify.primaryLabel.lowercased() == "spotify" {
                items.append("\(inlineEmphasis("Spotify")) was active in the background.")
            } else {
                items.append("\(inlineEmphasis("Spotify")) stayed active with \(inlineEmphasis(spotify.primaryLabel)) visible.")
            }
        }

        if let xSegment = driftSegments.first(where: { ($0.domain ?? "") == "x.com" || ($0.domain ?? "") == "twitter.com" }) {
            if xSegment.secondaryLabel == "Home feed" {
                items.append("You checked the \(inlineEmphasis("X")) home feed.")
            } else if let secondary = xSegment.secondaryLabel, !secondary.isEmpty {
                items.append("You opened \(inlineEmphasis(secondary)) on \(inlineEmphasis("X")).")
            }
        }

        if breakCount > 0 {
            items.append("You marked \(breakCount == 1 ? "a short break" : "\(breakCount) short breaks").")
        }

        return Array(items.prefix(4))
    }

    func overlayNarrative(for overlay: AttentionOverlay) -> String {
        switch overlay.kind {
        case .audio:
            if overlay.segment.appName.lowercased().contains("spotify") {
                return inlineEmphasis("Spotify")
            }
            return inlineEmphasis(overlay.segment.appName)
        case .note:
            return "A note"
        case .system:
            return "System context"
        case .context:
            return inlineEmphasis(overlay.segment.primaryLabel)
        }
    }

    func conciseNarrativeSummary(
        title: String,
        intent: SessionIntent,
        verdict: SessionVerdict,
        workPhrases: [String],
        driftPhrases: [String],
        firstNeutralSegment: TimelineSegment?,
        dominantContext: WorkContext?,
        audioOverlay: AttentionOverlay?
    ) -> String {
        let workClause = Array(workPhrases.prefix(1)).first
        let driftClause = Array(driftPhrases.prefix(1)).first
        let neutralClause = firstNeutralSegment.flatMap { activityClause(for: $0, role: .neutral, dominantContext: dominantContext) }
        let audioClause = audioOverlay.map(overlayNarrative(for:))

        switch verdict {
        case .matched:
            if !isIntentProgressSession(intent) {
                if let workClause {
                    return "You mostly did what you set out to do: \(workClause)."
                }
                return "You mostly stayed with the session you meant to have."
            }
            if let workClause {
                return "You mostly stayed with \(workClause), and the block moved \(inlineEmphasis(title)) forward."
            }
            return "You stayed with \(inlineEmphasis(title)) closely enough for the block to move forward."
        case .partiallyMatched:
            if !isIntentProgressSession(intent) {
                if let workClause, let driftClause {
                    return "You mostly stayed with \(workClause), but \(driftClause) pulled part of the block elsewhere."
                }
                if let workClause {
                    return "You spent most of the block \(workClause), but the session still wandered."
                }
                if let driftClause {
                    return "You spent much of the block \(driftClause), so the session only partly matched what you meant to do."
                }
                return "The session stayed near what you meant to do, but drift took over too often."
            }
            if let workClause, let driftClause {
                return "You stayed near \(workClause), but \(driftClause) kept \(inlineEmphasis(title)) from moving much."
            }
            if let workClause {
                return "You stayed near \(workClause), but the block never settled into enough sustained work to move \(inlineEmphasis(title)) much."
            }
            if let driftClause {
                return "You spent much of the block \(driftClause), so \(inlineEmphasis(title)) barely moved."
            }
            return "You stayed near \(inlineEmphasis(title)), but the block did not turn into steady progress."
        case .missed:
            if !isIntentProgressSession(intent) {
                if let driftClause {
                    return "You mostly spent the block \(driftClause) instead of staying with what you set out to do."
                }
                if let neutralClause {
                    return "You mostly spent the block \(neutralClause) instead of staying with what you set out to do."
                }
                return "This session turned into something other than what you set out to do."
            }
            if let driftClause {
                var sentence = "You mostly spent the block \(driftClause) instead of moving \(inlineEmphasis(title)) forward."
                if let audioClause {
                    sentence += " \(audioClause) also stayed in the background."
                }
                return sentence
            }
            if let neutralClause {
                return "You mostly spent the block \(neutralClause) instead of moving \(inlineEmphasis(title)) forward."
            }
            return "This block moved away from \(inlineEmphasis(title)) more than it moved it forward."
        }
    }

    func inlineCode(_ value: String) -> String {
        "**`\(value.replacingOccurrences(of: "`", with: ""))`**"
    }

    func inlineEmphasis(_ value: String) -> String {
        "**\(value.replacingOccurrences(of: "*", with: ""))**"
    }

    func isIntentProgressSession(_ intent: SessionIntent) -> Bool {
        switch intent.mode {
        case .watch, .listen, .browse:
            return false
        case .build, .review, .write, .research, .communicate, .admin, .mixed, .unknown:
            return true
        }
    }
}

private extension Sequence where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

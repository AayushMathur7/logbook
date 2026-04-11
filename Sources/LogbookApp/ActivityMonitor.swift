import AppKit
import ApplicationServices
import Foundation
import LogbookCore

@MainActor
final class ActivityMonitor {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastWindowKey = ""
    private var lastBrowserKey = ""
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var isUserIdle = false
    private let idleThreshold: TimeInterval = 5 * 60
    
    var onEvent: ((ActivityEvent) -> Void)?
    
    func start() {
        stop()
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        isUserIdle = currentIdleSeconds() >= idleThreshold
        recordFrontmostApp(reason: .appActivated)

        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            
            let appName = app.localizedName
            let bundleID = app.bundleIdentifier
            let processID = app.processIdentifier
            
            DispatchQueue.main.async { [weak self] in
                self?.handleAppActivation(appName: appName, bundleID: bundleID, processID: processID)
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            let appName = app.localizedName
            let bundleID = app.bundleIdentifier

            DispatchQueue.main.async { [weak self] in
                self?.emit(event: ActivityEvent(
                    occurredAt: Date(),
                    source: .workspace,
                    kind: .appLaunched,
                    appName: appName,
                    bundleID: bundleID
                ))
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            let appName = app.localizedName
            let bundleID = app.bundleIdentifier

            DispatchQueue.main.async { [weak self] in
                self?.emit(event: ActivityEvent(
                    occurredAt: Date(),
                    source: .workspace,
                    kind: .appTerminated,
                    appName: appName,
                    bundleID: bundleID
                ))
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.emitSystemEvent(kind: .systemWoke)
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.emitSystemEvent(kind: .systemSlept)
            }
        })
        
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.poll()
            }
        }
    }
    
    func stop() {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        workspaceObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func handleAppActivation(appName: String?, bundleID: String?, processID: pid_t) {
        let browserContext = BrowserInspector.activeTabContext(for: appName)
        let finderPath = appName == "Finder" ? FinderInspector.currentPath() : nil
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .workspace,
            kind: .appActivated,
            appName: appName,
            bundleID: bundleID,
            windowTitle: AccessibilityInspector.focusedWindowTitle(for: processID),
            resourceTitle: browserContext?.title,
            resourceURL: browserContext?.url,
            workingDirectory: finderPath
        ))
    }
    
    private func poll() {
        recordFrontmostWindowIfNeeded()
        recordBrowserContextIfNeeded()
        recordClipboardIfNeeded()
        recordIdleStateIfNeeded()
    }
    
    private func recordFrontmostApp(reason: ActivityKind) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return
        }

        let browserContext = BrowserInspector.activeTabContext(for: app.localizedName)
        let finderPath = app.localizedName == "Finder" ? FinderInspector.currentPath() : nil
        
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .workspace,
            kind: reason,
            appName: app.localizedName,
            bundleID: app.bundleIdentifier,
            windowTitle: AccessibilityInspector.focusedWindowTitle(for: app.processIdentifier),
            resourceTitle: browserContext?.title,
            resourceURL: browserContext?.url,
            domain: browserContext?.url.flatMap(Self.domain(from:)),
            workingDirectory: finderPath
        ))

        if let browserContext, isBrowserApp(app.localizedName) {
            emitBrowserEvent(
                kind: .tabFocused,
                appName: app.localizedName,
                bundleID: app.bundleIdentifier,
                processID: app.processIdentifier,
                browserContext: browserContext
            )
        }
    }
    
    private func recordFrontmostWindowIfNeeded() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return
        }

        let title = AccessibilityInspector.focusedWindowTitle(for: app.processIdentifier)
        let currentKey = "\(app.bundleIdentifier ?? app.localizedName ?? "unknown")|\(title ?? "")"
        
        guard currentKey != lastWindowKey else {
            return
        }

        lastWindowKey = currentKey
        let browserContext = BrowserInspector.activeTabContext(for: app.localizedName)
        let finderPath = app.localizedName == "Finder" ? FinderInspector.currentPath() : nil
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .accessibility,
            kind: .windowChanged,
            appName: app.localizedName,
            bundleID: app.bundleIdentifier,
            windowTitle: title,
            resourceTitle: browserContext?.title,
            resourceURL: browserContext?.url,
            domain: browserContext?.url.flatMap(Self.domain(from:)),
            workingDirectory: finderPath
        ))
    }

    private func recordBrowserContextIfNeeded() {
        guard let app = NSWorkspace.shared.frontmostApplication, isBrowserApp(app.localizedName) else {
            return
        }

        guard let browserContext = BrowserInspector.activeTabContext(for: app.localizedName) else {
            return
        }

        let browserKey = Self.browserKey(appName: app.localizedName, context: browserContext)
        guard !browserKey.isEmpty else {
            return
        }

        guard browserKey != lastBrowserKey else {
            return
        }

        let kind: ActivityKind = lastBrowserKey.isEmpty ? .tabFocused : .tabChanged
        emitBrowserEvent(
            kind: kind,
            appName: app.localizedName,
            bundleID: app.bundleIdentifier,
            processID: app.processIdentifier,
            browserContext: browserContext
        )
    }

    private func emit(event: ActivityEvent) {
        lastWindowKey = "\(event.bundleID ?? event.appName ?? "unknown")|\(event.windowTitle ?? "")"
        if let appName = event.appName, isBrowserApp(appName) {
            let browserKey = Self.browserKey(
                appName: appName,
                context: BrowserContext(title: event.resourceTitle, url: event.resourceURL)
            )
            if !browserKey.isEmpty {
                lastBrowserKey = browserKey
            }
        }
        onEvent?(event)
    }

    private func recordClipboardIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount

        let preview = clipboardPreview(from: pasteboard)
        guard preview != nil else { return }

        let app = NSWorkspace.shared.frontmostApplication
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .system,
            kind: .clipboardChanged,
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            windowTitle: AccessibilityInspector.focusedWindowTitle(for: app?.processIdentifier ?? 0),
            domain: BrowserInspector.activeTabContext(for: app?.localizedName)?.url.flatMap(Self.domain(from:)),
            clipboardPreview: preview
        ))
    }

    private func recordIdleStateIfNeeded() {
        let idleSeconds = currentIdleSeconds()
        if !isUserIdle && idleSeconds >= idleThreshold {
            isUserIdle = true
            emitPresenceEvent(kind: .userIdle)
        } else if isUserIdle && idleSeconds < 2 {
            isUserIdle = false
            emitPresenceEvent(kind: .userResumed)
        }
    }

    private func emitPresenceEvent(kind: ActivityKind) {
        let app = NSWorkspace.shared.frontmostApplication
        let browserContext = BrowserInspector.activeTabContext(for: app?.localizedName)
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .presence,
            kind: kind,
            appName: app?.localizedName,
            bundleID: app?.bundleIdentifier,
            windowTitle: AccessibilityInspector.focusedWindowTitle(for: app?.processIdentifier ?? 0),
            resourceTitle: browserContext?.title,
            resourceURL: browserContext?.url,
            domain: browserContext?.url.flatMap(Self.domain(from:))
        ))
    }

    private func emitSystemEvent(kind: ActivityKind) {
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .system,
            kind: kind
        ))
    }

    private func emitBrowserEvent(
        kind: ActivityKind,
        appName: String?,
        bundleID: String?,
        processID: pid_t,
        browserContext: BrowserContext
    ) {
        emit(event: ActivityEvent(
            occurredAt: Date(),
            source: .browser,
            kind: kind,
            appName: appName,
            bundleID: bundleID,
            windowTitle: AccessibilityInspector.focusedWindowTitle(for: processID),
            resourceTitle: browserContext.title,
            resourceURL: browserContext.url,
            domain: browserContext.url.flatMap(Self.domain(from:))
        ))
    }

    private func currentIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    private func isBrowserApp(_ appName: String?) -> Bool {
        guard let appName else { return false }
        let lower = appName.lowercased()
        return lower.contains("chrome")
            || lower.contains("safari")
            || lower.contains("arc")
            || lower.contains("brave")
            || lower.contains("edge")
            || lower.contains("firefox")
    }

    private static func browserKey(appName: String?, context: BrowserContext) -> String {
        [
            appName ?? "",
            context.title ?? "",
            context.url ?? "",
        ].joined(separator: "\u{001F}")
    }

    private static func domain(from urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return nil
        }

        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func clipboardPreview(from pasteboard: NSPasteboard) -> String? {
        if let value = pasteboard.string(forType: .URL), value.isEmpty == false {
            return truncatedClipboard(value)
        }
        if let value = pasteboard.string(forType: .string), value.isEmpty == false {
            return truncatedClipboard(value)
        }
        return nil
    }

    private func truncatedClipboard(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 120)
        return "\(trimmed[..<index])..."
    }
}

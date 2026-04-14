import AppKit
import Combine
import SwiftUI

@MainActor
enum LogbookAppEnvironment {
    static let model = AppModel()
}

@MainActor
enum LogbookWindowController {
    static weak var controller: LogbookAppController?

    static func showMainWindow() {
        controller?.showMainWindow()
    }

    static func quitApp() {
        controller?.quitApp()
    }

    static func configure(_ window: NSWindow) {
        window.title = "LogBook"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenNone)
    }
}

@MainActor
final class LogbookAppController: NSObject, NSApplicationDelegate {
    private let model = LogbookAppEnvironment.model
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        LogbookWindowController.controller = self
        installMainMenuIfNeeded()
        installMainWindowIfNeeded()
        installStatusItemIfNeeded()
        startStatusRefreshLoop()
        refreshStatusItem()
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusTimer?.invalidate()
    }

    func showMainWindow() {
        installMainWindowIfNeeded()
        guard let window = mainWindow else { return }
        LogbookWindowController.configure(window)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    private func installMainWindowIfNeeded() {
        guard mainWindow == nil else { return }

        let rootView = ContentView(model: model)
            .preferredColorScheme(.dark)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 728, height: 500))
        window.minSize = NSSize(width: 728, height: 500)
        window.isReleasedWhenClosed = false
        window.center()
        LogbookWindowController.configure(window)
        mainWindow = window
    }

    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }

        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "LogBook"

        appMenu.addItem(
            withTitle: "Open \(appName)",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ","
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let showItem = NSMenuItem(
            title: "Show \(appName)",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: "0"
        )
        showItem.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(showItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        statusItem = item
        installStatusMenuIfNeeded()

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        model.$surfaceState
            .receive(on: RunLoop.main)
            .scan((previous: model.surfaceState, current: model.surfaceState)) { state, newValue in
                (previous: state.current, current: newValue)
            }
            .sink { [weak self] state in
                guard let self else { return }
                guard state.previous == .running, state.current != .running else { return }
                self.showMainWindow()
            }
            .store(in: &cancellables)
    }

    private func installStatusMenuIfNeeded() {
        guard statusMenu == nil else { return }
        let menu = NSMenu()
        statusMenu = menu
        statusItem?.menu = menu
    }

    private func startStatusRefreshLoop() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusItem()
            }
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.image = NSImage(
            systemSymbolName: model.menuBarSymbolName,
            accessibilityDescription: "LogBook"
        )?.withSymbolConfiguration(configuration)
        button.imageScaling = .scaleProportionallyDown

        if let remaining = model.sessionRemainingLabel() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .baselineOffset: 0,
            ]
            let title = NSMutableAttributedString(
                string: "LogBook ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
            title.append(NSAttributedString(string: remaining, attributes: attributes))
            button.attributedTitle = title
        } else {
            button.attributedTitle = NSAttributedString(
                string: "LogBook",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]
            )
        }
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusMenu else { return }
        statusMenu.removeAllItems()

        let openItem = NSMenuItem(
            title: "Open LogBook",
            action: #selector(openMainWindowFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        statusMenu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit LogBook",
            action: #selector(quitFromMenu),
            keyEquivalent: ""
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    @objc private func openMainWindowFromMenu(_ sender: Any?) {
        showMainWindow()
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        showMainWindow()
        model.requestSettingsSheet()
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        quitApp()
    }
}

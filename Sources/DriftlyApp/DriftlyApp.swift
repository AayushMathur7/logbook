import AppKit
import Combine
import SwiftUI

@MainActor
enum DriftlyWindowStyle {
    static func configure(_ window: NSWindow) {
        window.title = "Driftly"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenNone)
    }
}

@MainActor
final class DriftlyAppController: NSObject, NSApplicationDelegate {
    private let model: AppModel
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var statusTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    convenience override init() {
        self.init(model: AppModel())
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
        DriftlyWindowStyle.configure(window)
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
        DriftlyWindowStyle.configure(window)
        mainWindow = window
    }

    private func installMainMenuIfNeeded() {
        guard NSApp.mainMenu == nil else { return }

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Driftly"
        let mainMenu = NSMenu(title: appName)

        let appMenuItem = NSMenuItem()
        appMenuItem.title = appName
        let appMenu = NSMenu(title: appName)

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
        windowMenuItem.title = "Window"
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
        item.button?.imagePosition = .imageOnly
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
        let menu = NSMenu(title: "Driftly")
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
        if let elapsed = model.sessionElapsedLabel() {
            button.image = DriftlyBrandImageFactory.sessionMenuBarImage(elapsed: elapsed)
        } else {
            button.image = DriftlyBrandImageFactory.defaultMenuBarImage
        }
        button.imageScaling = .scaleProportionallyDown
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        guard let statusMenu else { return }
        statusMenu.removeAllItems()

        let openItem = NSMenuItem(
            title: "Open Driftly",
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
            title: "Quit Driftly",
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

package enum DriftlyAppLauncher {
    @MainActor
    package static func run() {
        if PatternReplayCommand.shouldRun(arguments: CommandLine.arguments) {
            PatternReplayCommand.runAndExit(arguments: Array(CommandLine.arguments.dropFirst()))
        }

        if ReviewReplayCommand.shouldRun(arguments: CommandLine.arguments) {
            ReviewReplayCommand.runAndExit(arguments: Array(CommandLine.arguments.dropFirst()))
        }

        let application = NSApplication.shared
        let delegate = MainActor.assumeIsolated { DriftlyAppController() }
        application.delegate = delegate
        application.run()
    }
}

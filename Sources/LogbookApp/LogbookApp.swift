import AppKit
import LogbookCore
import SwiftUI

final class LogbookAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.styleMask.insert(.fullSizeContentView)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@main
struct LogbookApp: App {
    @NSApplicationDelegateAdaptor(LogbookAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    
    var body: some Scene {
        WindowGroup("Log Book") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 700, height: 500)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

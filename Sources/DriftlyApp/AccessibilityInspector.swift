import ApplicationServices
import AppKit
import Foundation

enum AccessibilityInspector {
    static let settingsURLs: [URL] = [
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!,
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!,
    ]

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        for url in settingsURLs {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
    
    static func focusedWindowTitle(for processID: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processID)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard result == .success, let windowElement = focusedWindow else {
            return nil
        }
        
        let windowAXElement = unsafeBitCast(windowElement, to: AXUIElement.self)
        
        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowAXElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )
        
        guard titleResult == .success, let title = titleValue as? String else {
            return nil
        }
        
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

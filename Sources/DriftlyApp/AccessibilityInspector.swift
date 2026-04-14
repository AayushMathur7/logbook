import ApplicationServices
import Foundation

enum AccessibilityInspector {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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

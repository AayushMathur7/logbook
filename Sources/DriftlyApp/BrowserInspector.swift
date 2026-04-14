import Foundation

struct BrowserContext {
    let title: String?
    let url: String?
}

enum BrowserInspector {
    static func activeTabContext(for appName: String?) -> BrowserContext? {
        guard let appName else { return nil }

        let script: String?
        switch appName {
        case "Google Chrome", "Arc", "Brave Browser", "Microsoft Edge":
            script = """
            tell application "\(appName)"
                if not (exists front window) then return ""
                set tabTitle to title of active tab of front window
                set tabURL to URL of active tab of front window
                return tabTitle & linefeed & tabURL
            end tell
            """
        case "Safari":
            script = """
            tell application "Safari"
                if not (exists front window) then return ""
                set tabTitle to name of current tab of front window
                set tabURL to URL of current tab of front window
                return tabTitle & linefeed & tabURL
            end tell
            """
        default:
            script = nil
        }

        guard let script, let result = AppleScriptRunner.run(script, timeout: 0.8) else {
            return nil
        }

        let parts = result.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let title = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeURL: String?
        if let url, url.hasPrefix("http://") || url.hasPrefix("https://") {
            safeURL = url
        } else {
            safeURL = nil
        }

        if title == nil && safeURL == nil { return nil }
        return BrowserContext(title: title?.nilIfEmpty, url: safeURL?.nilIfEmpty)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

public enum PathNoiseFilter {
    public static func shouldIgnoreFileActivity(path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path.lowercased()
        let lastPathComponent = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if standardized.contains("/temporaryitems/") {
            return true
        }

        if standardized.contains("/nsird_screencaptureui_") {
            return true
        }

        if standardized.contains("/var/folders/"),
           (lastPathComponent.hasPrefix(".tmp.") || lastPathComponent == ".tmp" || lastPathComponent.hasSuffix(".tmp")) {
            return true
        }

        if lastPathComponent.hasPrefix(".tmp.") || lastPathComponent.hasSuffix(".tmp") {
            return true
        }

        if lastPathComponent.hasSuffix(".swp") || lastPathComponent.hasSuffix(".swo") {
            return true
        }

        return false
    }
}

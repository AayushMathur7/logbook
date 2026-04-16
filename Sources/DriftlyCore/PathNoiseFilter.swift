import Foundation

public enum PathNoiseFilter {
    public static func shouldIgnoreFileActivity(path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let standardized = url.path.lowercased()
        let lastPathComponent = url.lastPathComponent.lowercased()

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

        if shouldIgnoreBrowserProfileChurn(path: standardized, lastPathComponent: lastPathComponent) {
            return true
        }

        return false
    }

    public static func isNoisyReviewLabel(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        if normalized.range(of: #"^[a-z]{20,}$"#, options: .regularExpression) != nil {
            return true
        }

        if normalized.contains("local extension settings")
            || normalized.contains("sync extension settings")
            || normalized.contains("browser extension settings") {
            return true
        }

        return false
    }

    private static func shouldIgnoreBrowserProfileChurn(path: String, lastPathComponent: String) -> Bool {
        guard browserProfileRoots.contains(where: { path.contains($0) }) else {
            return false
        }

        if browserNoiseDirectories.contains(where: { path.contains($0) }) {
            return true
        }

        if lastPathComponent.hasSuffix(".log") {
            return true
        }

        if lastPathComponent.range(of: #"^\d+\.log$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private static let browserProfileRoots = [
        "/library/application support/google/chrome/",
        "/library/application support/chromium/",
        "/library/application support/bravesoftware/brave-browser/",
        "/library/application support/microsoft edge/",
        "/library/application support/com.operasoftware.opera/",
        "/library/application support/arc/",
    ]

    private static let browserNoiseDirectories = [
        "/extensions/",
        "/local extension settings/",
        "/sync extension settings/",
        "/extension rules/",
        "/extension scripts/",
        "/service worker/",
        "/scriptcache/",
        "/code cache/",
        "/gpucache/",
        "/blob_storage/",
        "/indexeddb/",
        "/local storage/",
        "/session storage/",
        "/shared dictionary/",
        "/webrtc logs/",
        "/dawncache/",
    ]
}

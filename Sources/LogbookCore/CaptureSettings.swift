import Foundation

public struct OllamaConfiguration: Codable, Hashable {
    public var baseURLString: String
    public var modelName: String
    public var timeoutSeconds: Int
    public var storeDebugIO: Bool

    public init(
        baseURLString: String = "http://127.0.0.1:11434",
        modelName: String = "",
        timeoutSeconds: Int = 90,
        storeDebugIO: Bool = false
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.timeoutSeconds = timeoutSeconds
        self.storeDebugIO = storeDebugIO
    }
}

public struct CaptureSettings: Codable, Hashable {
    public var trackAccessibilityTitles: Bool
    public var trackBrowserContext: Bool
    public var trackFinderContext: Bool
    public var trackShellCommands: Bool
    public var trackFileSystemActivity: Bool
    public var trackClipboard: Bool
    public var trackPresence: Bool
    public var trackCalendarContext: Bool
    public var fileWatchRoots: [String]
    public var excludedAppBundleIDs: [String]
    public var excludedDomains: [String]
    public var excludedPathPrefixes: [String]
    public var redactedTitleBundleIDs: [String]
    public var droppedShellDirectoryPrefixes: [String]
    public var summaryOnlyDomains: [String]
    public var rawEventRetentionDays: Int
    public var ollama: OllamaConfiguration

    public init(
        trackAccessibilityTitles: Bool = true,
        trackBrowserContext: Bool = true,
        trackFinderContext: Bool = true,
        trackShellCommands: Bool = true,
        trackFileSystemActivity: Bool = true,
        trackClipboard: Bool = true,
        trackPresence: Bool = true,
        trackCalendarContext: Bool = true,
        fileWatchRoots: [String] = [],
        excludedAppBundleIDs: [String] = [],
        excludedDomains: [String] = [],
        excludedPathPrefixes: [String] = [],
        redactedTitleBundleIDs: [String] = [],
        droppedShellDirectoryPrefixes: [String] = [],
        summaryOnlyDomains: [String] = [],
        rawEventRetentionDays: Int = 30,
        ollama: OllamaConfiguration = OllamaConfiguration()
    ) {
        self.trackAccessibilityTitles = trackAccessibilityTitles
        self.trackBrowserContext = trackBrowserContext
        self.trackFinderContext = trackFinderContext
        self.trackShellCommands = trackShellCommands
        self.trackFileSystemActivity = trackFileSystemActivity
        self.trackClipboard = trackClipboard
        self.trackPresence = trackPresence
        self.trackCalendarContext = trackCalendarContext
        self.fileWatchRoots = fileWatchRoots
        self.excludedAppBundleIDs = excludedAppBundleIDs
        self.excludedDomains = excludedDomains
        self.excludedPathPrefixes = excludedPathPrefixes
        self.redactedTitleBundleIDs = redactedTitleBundleIDs
        self.droppedShellDirectoryPrefixes = droppedShellDirectoryPrefixes
        self.summaryOnlyDomains = summaryOnlyDomains
        self.rawEventRetentionDays = rawEventRetentionDays
        self.ollama = ollama
    }

    public static let `default` = CaptureSettings()
}
public enum PrivacyFilter {
    public static func apply(to event: ActivityEvent, settings: CaptureSettings) -> ActivityEvent? {
        guard let sourceAdjusted = applySourceSettings(to: event, settings: settings) else {
            return nil
        }

        let event = sourceAdjusted

        if let bundleID = event.bundleID?.lowercased(),
           containsExact(bundleID, in: settings.excludedAppBundleIDs) {
            return nil
        }

        if let domain = normalizedDomain(event.domain ?? event.resourceURL),
           containsDomain(domain, in: settings.excludedDomains) {
            return nil
        }

        if let candidatePath = event.path ?? event.workingDirectory,
           containsPath(candidatePath, in: settings.excludedPathPrefixes) {
            return nil
        }

        if event.kind == .commandStarted || event.kind == .commandFinished,
           let workingDirectory = event.workingDirectory,
           containsPath(workingDirectory, in: settings.droppedShellDirectoryPrefixes) {
            return nil
        }

        var redacted = event

        if let bundleID = event.bundleID?.lowercased(),
           containsExact(bundleID, in: settings.redactedTitleBundleIDs) {
            redacted = ActivityEvent(
                id: event.id,
                occurredAt: event.occurredAt,
                source: event.source,
                kind: event.kind,
                appName: event.appName,
                bundleID: event.bundleID,
                windowTitle: nil,
                path: event.path,
                resourceTitle: event.resourceTitle,
                resourceURL: event.resourceURL,
                domain: event.domain,
                clipboardPreview: event.clipboardPreview,
                noteText: event.noteText,
                relatedID: event.relatedID,
                command: event.command,
                workingDirectory: event.workingDirectory,
                commandStartedAt: event.commandStartedAt,
                commandFinishedAt: event.commandFinishedAt,
                durationMilliseconds: event.durationMilliseconds,
                exitCode: event.exitCode
            )
        }

        if let domain = normalizedDomain(redacted.domain ?? redacted.resourceURL),
           containsDomain(domain, in: settings.summaryOnlyDomains) {
            redacted = ActivityEvent(
                id: redacted.id,
                occurredAt: redacted.occurredAt,
                source: redacted.source,
                kind: redacted.kind,
                appName: redacted.appName,
                bundleID: redacted.bundleID,
                windowTitle: redacted.windowTitle,
                path: redacted.path,
                resourceTitle: domain,
                resourceURL: nil,
                domain: domain,
                clipboardPreview: redacted.clipboardPreview,
                noteText: redacted.noteText,
                relatedID: redacted.relatedID,
                command: redacted.command,
                workingDirectory: redacted.workingDirectory,
                commandStartedAt: redacted.commandStartedAt,
                commandFinishedAt: redacted.commandFinishedAt,
                durationMilliseconds: redacted.durationMilliseconds,
                exitCode: redacted.exitCode
            )
        }

        return redacted
    }
}

private extension PrivacyFilter {
    static func containsExact(_ value: String, in list: [String]) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return list.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
    }

    static func containsDomain(_ domain: String, in list: [String]) -> Bool {
        let normalized = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return list.contains { rule in
            let candidate = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !candidate.isEmpty else { return false }
            return normalized == candidate || normalized.hasSuffix(".\(candidate)")
        }
    }

    static func containsPath(_ path: String, in list: [String]) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return list.contains { rule in
            let candidate = URL(fileURLWithPath: rule).standardizedFileURL.path
            guard !candidate.isEmpty else { return false }
            return normalized == candidate || normalized.hasPrefix(candidate + "/")
        }
    }

    static func normalizedDomain(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let host = URL(string: rawValue)?.host?.lowercased(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let lowered = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return nil }
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }

    static func applySourceSettings(to event: ActivityEvent, settings: CaptureSettings) -> ActivityEvent? {
        if event.source == .accessibility && !settings.trackAccessibilityTitles {
            return nil
        }
        if event.source == .browser && !settings.trackBrowserContext {
            return nil
        }
        if event.source == .shell && !settings.trackShellCommands {
            return nil
        }
        if event.source == .fileSystem && !settings.trackFileSystemActivity {
            return nil
        }
        if event.source == .presence && !settings.trackPresence {
            return nil
        }
        if event.kind == .clipboardChanged && !settings.trackClipboard {
            return nil
        }

        let shouldStripWindowTitle = !settings.trackAccessibilityTitles
        let shouldStripBrowserContext = !settings.trackBrowserContext
        let shouldStripFinderContext = !settings.trackFinderContext
        let shouldStripClipboard = !settings.trackClipboard

        let isFinderContext = event.appName == "Finder"
            && (event.source == .workspace || event.source == .system || event.source == .presence)

        return ActivityEvent(
            id: event.id,
            occurredAt: event.occurredAt,
            source: event.source,
            kind: event.kind,
            appName: event.appName,
            bundleID: event.bundleID,
            windowTitle: shouldStripWindowTitle ? nil : event.windowTitle,
            path: event.path,
            resourceTitle: shouldStripBrowserContext ? nil : event.resourceTitle,
            resourceURL: shouldStripBrowserContext ? nil : event.resourceURL,
            domain: shouldStripBrowserContext ? nil : event.domain,
            clipboardPreview: shouldStripClipboard ? nil : event.clipboardPreview,
            noteText: event.noteText,
            relatedID: event.relatedID,
            command: event.command,
            workingDirectory: shouldStripFinderContext && isFinderContext ? nil : event.workingDirectory,
            commandStartedAt: event.commandStartedAt,
            commandFinishedAt: event.commandFinishedAt,
            durationMilliseconds: event.durationMilliseconds,
            exitCode: event.exitCode
        )
    }
}

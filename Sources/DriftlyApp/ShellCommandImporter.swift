import CryptoKit
import Foundation
import DriftlyCore

enum ShellCommandImporter {
    static func importEvents(existingEventIDs: Set<String>, settings: CaptureSettings) -> [ActivityEvent] {
        let url = DriftlyPaths.shellInboxURL
        
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        
        return contents
            .split(whereSeparator: \.isNewline)
            .flatMap { parse(line: String($0), existingEventIDs: existingEventIDs, settings: settings) }
    }
    
    private static func parse(line: String, existingEventIDs: Set<String>, settings: CaptureSettings) -> [ActivityEvent] {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 5 else { return [] }
        
        let finishedAt = parts[0]
        let startedAt = parts[1]
        let workingDirectory = String(parts[2])
        let exitCode = Int(parts[3])
        let command = parts[4...].joined(separator: "\t")
        
        let formatter = ISO8601DateFormatter()
        let startedDate = formatter.date(from: String(startedAt))
        let finishedDate = formatter.date(from: String(finishedAt)) ?? startedDate

        if shouldDropShellEvents(for: workingDirectory, settings: settings) {
            return []
        }

        guard let occurredAt = finishedDate ?? startedDate else {
            return []
        }

        let pathURL = URL(fileURLWithPath: workingDirectory)
        let startID = stableID(for: "\(startedAt)|\(workingDirectory)|start|\(command)")
        let finishID = stableID(for: "\(finishedAt)|\(workingDirectory)|\(parts[3])|\(command)")
        let durationMilliseconds: Int? = {
            guard let startedDate, let finishedDate else { return nil }
            return max(Int((finishedDate.timeIntervalSince(startedDate) * 1000).rounded()), 0)
        }()

        var events: [ActivityEvent] = []

        if let startedDate, !existingEventIDs.contains(startID) {
            events.append(
                ActivityEvent(
                    id: startID,
                    occurredAt: startedDate,
                    source: .shell,
                    kind: .commandStarted,
                    appName: "Terminal",
                    bundleID: "com.apple.Terminal",
                    windowTitle: pathURL.lastPathComponent,
                    path: pathURL.path,
                    command: command,
                    workingDirectory: workingDirectory,
                    commandStartedAt: startedDate
                )
            )
        }

        if !existingEventIDs.contains(finishID) {
            events.append(
                ActivityEvent(
                    id: finishID,
                    occurredAt: occurredAt,
                    source: .shell,
                    kind: .commandFinished,
                    appName: "Terminal",
                    bundleID: "com.apple.Terminal",
                    windowTitle: pathURL.lastPathComponent,
                    path: pathURL.path,
                    command: command,
                    workingDirectory: workingDirectory,
                    commandStartedAt: startedDate,
                    commandFinishedAt: finishedDate,
                    durationMilliseconds: durationMilliseconds,
                    exitCode: exitCode
                )
            )
        }

        return events
    }

    private static func shouldDropShellEvents(for workingDirectory: String, settings: CaptureSettings) -> Bool {
        let normalized = URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        return settings.droppedShellDirectoryPrefixes.contains { prefix in
            let candidate = URL(fileURLWithPath: prefix).standardizedFileURL.path
            guard !candidate.isEmpty else { return false }
            return normalized == candidate || normalized.hasPrefix(candidate + "/")
        }
    }
    
    private static func stableID(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

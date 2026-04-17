import Darwin
import Foundation
import DriftlyCore

enum ReviewDebugLogger {
    static func logReviewFailure(
        sessionTitle: String,
        error: String,
        prompt: String = "",
        rawResponse: String = ""
    ) {
        append(
            """
            [\(timestamp())] REVIEW FAILED
            Session: \(sessionTitle)
            Error: \(error)
            Prompt:
            \(blankFallback(prompt))
            Raw response:
            \(blankFallback(rawResponse))
            """
        )
    }

    private static func append(_ entry: String) {
        let url = DriftlyPaths.reviewDebugLogURL
        let payload = entry + "\n" + String(repeating: "-", count: 72) + "\n\n"
        guard let data = payload.data(using: .utf8) else { return }

        do {
            try FileManager.default.createDirectory(
                at: DriftlyPaths.appSupportDirectory,
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            fputs("Failed to write review debug log: \(error)\n", stderr)
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func blankFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<empty>" : value
    }
}

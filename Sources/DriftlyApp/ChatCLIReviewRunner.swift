import Darwin
import Foundation

enum ChatCLITool: String, Hashable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex:
            return "Codex CLI"
        case .claude:
            return "Claude Code"
        }
    }

    var installGuideURL: URL {
        switch self {
        case .codex:
            return URL(string: "https://developers.openai.com/codex/cli/")!
        case .claude:
            return URL(string: "https://docs.anthropic.com/en/docs/claude-code/setup")!
        }
    }

    var loginCommand: String {
        switch self {
        case .codex:
            return "codex login"
        case .claude:
            return "claude auth login"
        }
    }
}

struct ChatCLIStatus: Hashable {
    let installed: Bool
    let authenticated: Bool
    let version: String?
    let message: String
}

struct ChatCLIRunResult {
    let output: String
    let rawStdout: String
    let stderr: String
}

enum ChatCLIError: LocalizedError {
    case notInstalled(ChatCLITool)
    case notAuthenticated(ChatCLITool)
    case timedOut(ChatCLITool, Int)
    case emptyResponse(ChatCLITool)
    case executionFailed(ChatCLITool, String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(tool):
            return "\(tool.displayName) is not installed."
        case let .notAuthenticated(tool):
            return "\(tool.displayName) is installed, but you are not signed in yet."
        case let .timedOut(tool, seconds):
            return "\(tool.displayName) timed out after \(seconds) seconds."
        case let .emptyResponse(tool):
            return "\(tool.displayName) returned an empty response."
        case let .executionFailed(tool, message):
            return "\(tool.displayName) failed: \(message)"
        }
    }
}

private struct LoginShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private enum LoginShellRunner {
    static var userLoginShell: URL {
        if let entry = getpwuid(getuid()),
           let shellPath = String(validatingUTF8: entry.pointee.pw_shell),
           !shellPath.isEmpty {
            return URL(fileURLWithPath: shellPath)
        }
        return URL(fileURLWithPath: "/bin/zsh")
    }

    static func shellEscape(_ string: String) -> String {
        let sanitized = string.replacingOccurrences(of: "\0", with: "")
        let escaped = sanitized.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func run(_ command: String, timeout: TimeInterval = 30) -> LoginShellResult {
        let process = Process()
        process.executableURL = userLoginShell
        process.arguments = ["-l", "-i", "-c", command]
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return LoginShellResult(stdout: "", stderr: error.localizedDescription, exitCode: -1)
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return LoginShellResult(
                stdout: "",
                stderr: "Command timed out after \(Int(timeout)) seconds",
                exitCode: -2
            )
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return LoginShellResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

enum ChatCLIReviewRunner {
    static func detect(tool: ChatCLITool) -> ChatCLIStatus {
        let versionResult = LoginShellRunner.run("\(tool.rawValue) --version", timeout: 10)
        guard versionResult.exitCode == 0 else {
            return ChatCLIStatus(
                installed: false,
                authenticated: false,
                version: nil,
                message: "\(tool.displayName) was not found on this Mac."
            )
        }

        let version = versionResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first

        switch tool {
        case .codex:
            let statusResult = LoginShellRunner.run("codex login status", timeout: 10)
            let combinedOutput = "\(statusResult.stdout)\n\(statusResult.stderr)".lowercased()
            let authenticated = statusResult.exitCode == 0 && combinedOutput.contains("logged in")
            return ChatCLIStatus(
                installed: true,
                authenticated: authenticated,
                version: version,
                message: authenticated
                    ? "Codex CLI is installed and signed in."
                    : "Codex CLI is installed, but you still need to run `codex login`."
            )
        case .claude:
            let statusResult = LoginShellRunner.run("claude auth status", timeout: 10)
            let authenticated: Bool
            if let data = statusResult.stdout.data(using: .utf8),
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let loggedIn = payload["loggedIn"] as? Bool {
                authenticated = loggedIn
            } else {
                authenticated = statusResult.exitCode == 0 && statusResult.stdout.lowercased().contains("\"loggedin\": true")
            }

            return ChatCLIStatus(
                installed: true,
                authenticated: authenticated,
                version: version,
                message: authenticated
                    ? "Claude Code is installed and signed in."
                    : "Claude Code is installed, but you still need to run `claude auth login`."
            )
        }
    }

    static func runStructuredJSON(
        tool: ChatCLITool,
        prompt: String,
        schemaJSON: String,
        model: String?,
        timeoutSeconds: Int
    ) throws -> ChatCLIRunResult {
        let status = detect(tool: tool)
        guard status.installed else { throw ChatCLIError.notInstalled(tool) }
        guard status.authenticated else { throw ChatCLIError.notAuthenticated(tool) }

        let timeout = max(timeoutSeconds, 10)
        let workingDirectory = try ensureWorkingDirectory()
        let scratchDirectory = workingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }

        let schemaPath = scratchDirectory.appendingPathComponent("schema.json")
        try schemaJSON.write(to: schemaPath, atomically: true, encoding: .utf8)

        switch tool {
        case .codex:
            let outputPath = scratchDirectory.appendingPathComponent("output.json")
            let command = codexCommand(
                prompt: prompt,
                model: model,
                timeoutSeconds: timeout,
                schemaPath: schemaPath.path,
                outputPath: outputPath.path,
                workingDirectory: workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(tool, result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
            }

            let output = (try? String(contentsOf: outputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(output: output, rawStdout: result.stdout, stderr: result.stderr)
        case .claude:
            let command = claudeCommand(
                prompt: prompt,
                model: model,
                schemaJSON: schemaJSON,
                workingDirectory: workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(tool, result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
            }

            let output = try parseClaudeStructuredOutput(from: result.stdout)
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(output: output, rawStdout: result.stdout, stderr: result.stderr)
        }
    }

    static func runPlainText(
        tool: ChatCLITool,
        prompt: String,
        model: String?,
        timeoutSeconds: Int
    ) throws -> ChatCLIRunResult {
        let status = detect(tool: tool)
        guard status.installed else { throw ChatCLIError.notInstalled(tool) }
        guard status.authenticated else { throw ChatCLIError.notAuthenticated(tool) }

        let timeout = max(timeoutSeconds, 10)
        let workingDirectory = try ensureWorkingDirectory()

        switch tool {
        case .codex:
            let scratchDirectory = workingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratchDirectory) }

            let outputPath = scratchDirectory.appendingPathComponent("output.txt")
            let command = codexCommand(
                prompt: prompt,
                model: model,
                timeoutSeconds: timeout,
                schemaPath: nil,
                outputPath: outputPath.path,
                workingDirectory: workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(tool, result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
            }

            let output = (try? String(contentsOf: outputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(output: output, rawStdout: result.stdout, stderr: result.stderr)
        case .claude:
            let command = claudeCommand(
                prompt: prompt,
                model: model,
                schemaJSON: nil,
                workingDirectory: workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(tool, result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
            }

            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(output: output, rawStdout: result.stdout, stderr: result.stderr)
        }
    }

    private static func codexCommand(
        prompt: String,
        model: String?,
        timeoutSeconds: Int,
        schemaPath: String?,
        outputPath: String,
        workingDirectory: String
    ) -> String {
        var parts: [String] = [
            "cd \(LoginShellRunner.shellEscape(workingDirectory))",
            "&&",
            "exec",
            "codex",
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "-c",
            LoginShellRunner.shellEscape("rmcp_client=false"),
            "-c",
            LoginShellRunner.shellEscape("web_search=disabled"),
            "-o",
            LoginShellRunner.shellEscape(outputPath),
        ]

        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(contentsOf: ["-m", LoginShellRunner.shellEscape(model)])
        }

        if let schemaPath {
            parts.append(contentsOf: ["--output-schema", LoginShellRunner.shellEscape(schemaPath)])
        }

        parts.append("--")
        parts.append(LoginShellRunner.shellEscape(prompt))
        return parts.joined(separator: " ")
    }

    private static func claudeCommand(
        prompt: String,
        model: String?,
        schemaJSON: String?,
        workingDirectory: String
    ) -> String {
        var parts: [String] = [
            "cd \(LoginShellRunner.shellEscape(workingDirectory))",
            "&&",
            "exec",
            "claude",
            "-p",
            "--tools",
            LoginShellRunner.shellEscape(""),
            "--strict-mcp-config",
        ]

        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(contentsOf: ["--model", LoginShellRunner.shellEscape(model)])
        }

        if let schemaJSON {
            parts.append(contentsOf: ["--output-format", "json"])
            parts.append(contentsOf: ["--json-schema", LoginShellRunner.shellEscape(schemaJSON)])
        }

        parts.append("--")
        parts.append(LoginShellRunner.shellEscape(prompt))
        return parts.joined(separator: " ")
    }

    private static func parseClaudeStructuredOutput(from stdout: String) throws -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return trimmed
        }

        if let structured = payload["structured_output"] {
            let structuredData = try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys])
            return String(data: structuredData, encoding: .utf8) ?? trimmed
        }

        if let result = payload["result"] as? String {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func ensureWorkingDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Driftly/chatcli", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

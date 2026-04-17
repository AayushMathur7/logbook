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

package struct ChatCLIRunResult {
    package let prompt: String
    package let output: String
    package let rawStdout: String
    package let stderr: String

    package init(prompt: String, output: String, rawStdout: String, stderr: String) {
        self.prompt = prompt
        self.output = output
        self.rawStdout = rawStdout
        self.stderr = stderr
    }
}

package struct ChatCLIWorkspaceFile {
    package let relativePath: String
    package let content: String
}

private enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if container.decodeNil() {
                self = .null
                return
            }
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
                return
            }
            if let value = try? container.decode(Double.self) {
                self = .number(value)
                return
            }
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
        }

        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: JSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        var container = try decoder.unkeyedContainer()
        var array: [JSONValue] = []
        while !container.isAtEnd {
            array.append(try container.decode(JSONValue.self))
        }
        self = .array(array)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .object(object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
            }
        case let .array(array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ClaudeAuthStatusPayload: Decodable {
    let loggedIn: Bool
}

private struct ClaudeStructuredOutputEnvelope: Decodable {
    let structuredOutput: JSONValue?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case structuredOutput = "structured_output"
        case result
    }
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
    private static func resolvedExecutablePath(for tool: ChatCLITool) -> String? {
        var candidates: [String] = []
        var seen = Set<String>()

        func appendCandidate(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard seen.insert(trimmed).inserted else { return }
            candidates.append(trimmed)
        }

        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in environmentPath.split(separator: ":").map(String.init) {
            appendCandidate(URL(fileURLWithPath: directory).appendingPathComponent(tool.rawValue).path)
        }

        let homeDirectory = NSHomeDirectory()
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/bin",
            "/Applications/Codex.app/Contents/Resources"
        ]
        for directory in commonDirectories {
            appendCandidate(URL(fileURLWithPath: directory).appendingPathComponent(tool.rawValue).path)
        }

        let shellLookup = LoginShellRunner.run("command -v \(tool.rawValue)", timeout: 5)
        if shellLookup.exitCode == 0 {
            let discoveredPath = shellLookup.stdout
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.hasPrefix("/") }
            appendCandidate(discoveredPath)
        }

        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    static func detect(tool: ChatCLITool) -> ChatCLIStatus {
        guard let executablePath = resolvedExecutablePath(for: tool) else {
            return ChatCLIStatus(
                installed: false,
                authenticated: false,
                version: nil,
                message: "\(tool.displayName) was not found on this Mac."
            )
        }

        let executable = LoginShellRunner.shellEscape(executablePath)
        let versionResult = LoginShellRunner.run("\(executable) --version", timeout: 10)
        guard versionResult.exitCode == 0 else {
            return ChatCLIStatus(
                installed: false,
                authenticated: false,
                version: nil,
                message: "\(tool.displayName) was found at \(executablePath), but Driftly could not run it."
            )
        }

        let version = versionResult.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first

        switch tool {
        case .codex:
            let statusResult = LoginShellRunner.run("\(executable) login status", timeout: 10)
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
            let statusResult = LoginShellRunner.run("\(executable) auth status", timeout: 10)
            let authenticated = decodeClaudeAuthStatus(from: statusResult.stdout)
                ?? (statusResult.exitCode == 0 && statusResult.stdout.lowercased().contains("\"loggedin\": true"))

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
        timeoutSeconds: Int,
        insightWritingSkill: String? = nil,
        workspaceFiles: [ChatCLIWorkspaceFile] = []
    ) throws -> ChatCLIRunResult {
        let status = detect(tool: tool)
        guard status.installed else { throw ChatCLIError.notInstalled(tool) }
        guard status.authenticated else { throw ChatCLIError.notAuthenticated(tool) }

        let timeout = max(timeoutSeconds, 10)
        let baseDirectory = try ensureWorkingDirectory()
        let runtimeContext = try prepareRuntimeContext(
            tool: tool,
            insightWritingSkill: insightWritingSkill,
            workspaceFiles: workspaceFiles
        )
        let scratchDirectory = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        defer { try? FileManager.default.removeItem(at: runtimeContext.workingDirectory) }
        let effectivePrompt = promptWithSkillHint(prompt, includeSkillHint: insightWritingSkill?.nilIfBlank != nil)
        let executablePath = resolvedExecutablePath(for: tool)

        let schemaPath = scratchDirectory.appendingPathComponent("schema.json")
        try schemaJSON.write(to: schemaPath, atomically: true, encoding: .utf8)

        switch tool {
        case .codex:
            let outputPath = scratchDirectory.appendingPathComponent("output.json")
            let command = codexCommand(
                executablePath: executablePath,
                prompt: effectivePrompt,
                model: model,
                timeoutSeconds: timeout,
                schemaPath: schemaPath.path,
                outputPath: outputPath.path,
                workingDirectory: runtimeContext.workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(
                    tool,
                    sanitizedUserVisibleMessage(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
                )
            }

            let output = (try? String(contentsOf: outputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(prompt: prompt, output: output, rawStdout: result.stdout, stderr: result.stderr)
        case .claude:
            let command = claudeCommand(
                executablePath: executablePath,
                prompt: effectivePrompt,
                model: model,
                schemaJSON: schemaJSON,
                workingDirectory: runtimeContext.workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(
                    tool,
                    sanitizedUserVisibleMessage(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
                )
            }

            let output = try parseClaudeStructuredOutput(from: result.stdout)
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(prompt: prompt, output: output, rawStdout: result.stdout, stderr: result.stderr)
        }
    }

    static func runPlainText(
        tool: ChatCLITool,
        prompt: String,
        model: String?,
        timeoutSeconds: Int,
        insightWritingSkill: String? = nil,
        workspaceFiles: [ChatCLIWorkspaceFile] = []
    ) throws -> ChatCLIRunResult {
        let status = detect(tool: tool)
        guard status.installed else { throw ChatCLIError.notInstalled(tool) }
        guard status.authenticated else { throw ChatCLIError.notAuthenticated(tool) }

        let timeout = max(timeoutSeconds, 10)
        let baseDirectory = try ensureWorkingDirectory()
        let runtimeContext = try prepareRuntimeContext(
            tool: tool,
            insightWritingSkill: insightWritingSkill,
            workspaceFiles: workspaceFiles
        )
        let scratchDirectory = baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }
        defer { try? FileManager.default.removeItem(at: runtimeContext.workingDirectory) }
        let effectivePrompt = promptWithSkillHint(prompt, includeSkillHint: insightWritingSkill?.nilIfBlank != nil)
        let executablePath = resolvedExecutablePath(for: tool)

        switch tool {
        case .codex:
            let outputPath = scratchDirectory.appendingPathComponent("output.txt")
            let command = codexCommand(
                executablePath: executablePath,
                prompt: effectivePrompt,
                model: model,
                timeoutSeconds: timeout,
                schemaPath: nil,
                outputPath: outputPath.path,
                workingDirectory: runtimeContext.workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(
                    tool,
                    sanitizedUserVisibleMessage(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
                )
            }

            let output = (try? String(contentsOf: outputPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(prompt: prompt, output: output, rawStdout: result.stdout, stderr: result.stderr)
        case .claude:
            let command = claudeCommand(
                executablePath: executablePath,
                prompt: effectivePrompt,
                model: model,
                schemaJSON: nil,
                workingDirectory: runtimeContext.workingDirectory.path
            )
            let result = LoginShellRunner.run(command, timeout: TimeInterval(timeout))
            if result.exitCode == -2 {
                throw ChatCLIError.timedOut(tool, timeout)
            }
            if result.exitCode != 0 {
                throw ChatCLIError.executionFailed(
                    tool,
                    sanitizedUserVisibleMessage(result.stderr.nilIfBlank ?? result.stdout.nilIfBlank ?? "Unknown error")
                )
            }

            let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                throw ChatCLIError.emptyResponse(tool)
            }

            return ChatCLIRunResult(prompt: prompt, output: output, rawStdout: result.stdout, stderr: result.stderr)
        }
    }

    private struct CLIRuntimeContext {
        let workingDirectory: URL
    }

    private static func prepareRuntimeContext(
        tool: ChatCLITool,
        insightWritingSkill: String?,
        workspaceFiles: [ChatCLIWorkspaceFile]
    ) throws -> CLIRuntimeContext {
        let baseDirectory = try ensureWorkingDirectory()
        let directory = baseDirectory
            .appendingPathComponent(tool.rawValue, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try refreshProviderContext(
            in: directory,
            tool: tool,
            insightWritingSkill: insightWritingSkill,
            workspaceFiles: workspaceFiles
        )
        return CLIRuntimeContext(workingDirectory: directory)
    }

    private static func refreshProviderContext(
        in directory: URL,
        tool: ChatCLITool,
        insightWritingSkill: String?,
        workspaceFiles: [ChatCLIWorkspaceFile]
    ) throws {
        switch tool {
        case .codex:
            let agentsPath = directory.appendingPathComponent("AGENTS.md")
            try writeFileIfNeeded(DriftlyAgentContext.codexAgentsMarkdown(), to: agentsPath)

            let skillDirectory = directory
                .appendingPathComponent(".agents", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent(DriftlyAgentContext.skillName, isDirectory: true)
            try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
            try writeFileIfNeeded(DriftlyAgentContext.skillMarkdown(), to: skillDirectory.appendingPathComponent("SKILL.md"))
            try writeFileIfNeeded(
                DriftlyAgentContext.openAIMetadataYAML(),
                to: skillDirectory
                    .appendingPathComponent("agents", isDirectory: true)
                    .appendingPathComponent("openai.yaml")
            )
            try writeFileIfNeeded(
                DriftlyAgentContext.trackedEvidenceMarkdown(),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("what-driftly-tracks.md")
            )
            try writeFileIfNeeded(
                DriftlyAgentContext.outputStyleMarkdown(),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("output-style.md")
            )
            try writeFileIfNeeded(
                DriftlyAgentContext.recentPatternsMarkdown(from: insightWritingSkill),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("recent-patterns.md")
            )
        case .claude:
            let claudePath = directory.appendingPathComponent("CLAUDE.md")
            try writeFileIfNeeded(DriftlyAgentContext.claudeMarkdown(), to: claudePath)

            let skillDirectory = directory
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent(DriftlyAgentContext.skillName, isDirectory: true)
            try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
            try writeFileIfNeeded(DriftlyAgentContext.skillMarkdown(), to: skillDirectory.appendingPathComponent("SKILL.md"))
            try writeFileIfNeeded(
                DriftlyAgentContext.trackedEvidenceMarkdown(),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("what-driftly-tracks.md")
            )
            try writeFileIfNeeded(
                DriftlyAgentContext.outputStyleMarkdown(),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("output-style.md")
            )
            try writeFileIfNeeded(
                DriftlyAgentContext.recentPatternsMarkdown(from: insightWritingSkill),
                to: skillDirectory
                    .appendingPathComponent("references", isDirectory: true)
                    .appendingPathComponent("recent-patterns.md")
            )
        }

        for file in workspaceFiles {
            let path = directory.appendingPathComponent(file.relativePath)
            try writeFileIfNeeded(file.content, to: path)
        }
    }

    private static func promptWithSkillHint(_ prompt: String, includeSkillHint: Bool) -> String {
        guard includeSkillHint else { return prompt }
        return "Use the driftly-insight-writing skill for this task.\n\n\(prompt)"
    }

    private static func sanitizedUserVisibleMessage(_ value: String) -> String {
        let strippedLines = value
            .components(separatedBy: .newlines)
            .filter { line in
                let lowered = line.lowercased()
                return !lowered.contains("developers.openai.com/codex/skills")
                    && !lowered.contains("https://developers.openai.com")
                    && !lowered.contains("http://developers.openai.com")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return strippedLines.nilIfBlank ?? "Unknown error"
    }

    private static func writeFileIfNeeded(_ content: String, to path: URL) throws {
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = try? String(contentsOf: path, encoding: .utf8)
        guard existing != content else { return }
        try content.write(to: path, atomically: true, encoding: .utf8)
    }

    private static func codexCommand(
        executablePath: String?,
        prompt: String,
        model: String?,
        timeoutSeconds: Int,
        schemaPath: String?,
        outputPath: String,
        workingDirectory: String
    ) -> String {
        let executable = LoginShellRunner.shellEscape(executablePath ?? "codex")
        var parts: [String] = [
            "cd \(LoginShellRunner.shellEscape(workingDirectory))",
            "&&",
            "exec",
            executable,
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
        executablePath: String?,
        prompt: String,
        model: String?,
        schemaJSON: String?,
        workingDirectory: String
    ) -> String {
        let executable = LoginShellRunner.shellEscape(executablePath ?? "claude")
        var parts: [String] = [
            "cd \(LoginShellRunner.shellEscape(workingDirectory))",
            "&&",
            "exec",
            executable,
            "-p",
            "--tools",
            LoginShellRunner.shellEscape("default"),
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

    private static func decodeClaudeAuthStatus(from stdout: String) -> Bool? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ClaudeAuthStatusPayload.self, from: data).loggedIn
    }

    private static func parseClaudeStructuredOutput(from stdout: String) throws -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw ChatCLIError.executionFailed(.claude, "Claude Code returned non-UTF8 structured output.")
        }
        let payload = try JSONDecoder().decode(ClaudeStructuredOutputEnvelope.self, from: data)

        if let structured = payload.structuredOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let structuredData = try encoder.encode(structured)
            guard let output = String(data: structuredData, encoding: .utf8) else {
                throw ChatCLIError.executionFailed(.claude, "Claude Code returned structured output that could not be re-encoded.")
            }
            return output
        }

        if let result = payload.result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw ChatCLIError.executionFailed(.claude, "Claude Code did not return a structured payload.")
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

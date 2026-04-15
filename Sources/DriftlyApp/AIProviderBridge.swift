import Foundation
import DriftlyCore

struct OllamaModel: Identifiable, Hashable {
    let name: String
    let sizeBytes: Int64?

    var id: String { name }
}

struct LocalReviewRun {
    let providerTitle: String
    let prompt: String
    let rawResponse: String
    let review: SessionReview
}

protocol LocalReviewProvider {
    func availableModels(settings: CaptureSettings) async throws -> [OllamaModel]
    func generateReview(
        settings: CaptureSettings,
        title: String,
        personName: String?,
        contextPattern: ContextPatternSnapshot?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) async throws -> LocalReviewRun
    func generateFocusGuardNudge(
        settings: CaptureSettings,
        goal: String,
        assessmentReason: String,
        driftLabels: [String],
        matchedLabels: [String],
        events: [ActivityEvent]
    ) async throws -> String
    func summarizeLearningMemory(
        settings: CaptureSettings,
        personName: String?,
        feedbackExamples: [SessionReviewFeedbackExample]
    ) async throws -> SessionReviewLearningMemory
}

enum AIProviderBridge: LocalReviewProvider {
    case ollama
    case codex
    case claude

    static func provider(for provider: AIReviewProvider) -> AIProviderBridge {
        switch provider {
        case .ollama:
            return .ollama
        case .codex:
            return .codex
        case .claude:
            return .claude
        }
    }

    func availableModels(settings: CaptureSettings) async throws -> [OllamaModel] {
        guard case .ollama = self else {
            return []
        }

        let endpoint = try validatedBaseURL(from: settings.ollama).appending(path: "/api/tags")
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return response.models
            .map { OllamaModel(name: $0.name, sizeBytes: $0.size) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func generateReview(
        settings: CaptureSettings,
        title: String,
        personName: String?,
        contextPattern: ContextPatternSnapshot?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) async throws -> LocalReviewRun {
        let primaryPrompt = sessionReviewPrompt(
            title: title,
            personName: personName,
            contextPattern: contextPattern,
            reviewLearnings: reviewLearnings,
            feedbackExamples: feedbackExamples,
            startedAt: startedAt,
            endedAt: endedAt,
            events: events,
            segments: segments
        )

        switch self {
        case .ollama:
            let configuration = settings.ollama
            let baseURL = try validatedBaseURL(from: configuration)
            guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OllamaError.missingModel
            }

            return try await generateOllamaReviewRun(
                configuration: configuration,
                baseURL: baseURL,
                prompt: primaryPrompt,
                title: title,
                personName: personName,
                startedAt: startedAt,
                endedAt: endedAt,
                events: events,
                segments: segments
            )
        case .codex, .claude:
            let tool = chatCLITool
            let run = try ChatCLIReviewRunner.runStructuredJSON(
                tool: tool,
                prompt: primaryPrompt,
                schemaJSON: structuredOutputSchemaJSON(for: .sessionReview),
                model: configuredCLIModel(from: settings.chatCLI),
                timeoutSeconds: settings.chatCLI.timeoutSeconds
            )
            let review = try parseSessionReview(
                from: run.output,
                title: title,
                personName: personName,
                startedAt: startedAt,
                endedAt: endedAt,
                events: events,
                segments: segments
            )
            return LocalReviewRun(
                providerTitle: tool.displayName,
                prompt: primaryPrompt,
                rawResponse: run.output,
                review: review
            )
        }
    }

    func summarizeLearningMemory(
        settings: CaptureSettings,
        personName: String?,
        feedbackExamples: [SessionReviewFeedbackExample]
    ) async throws -> SessionReviewLearningMemory {
        let prompt = feedbackLearningPrompt(personName: personName, feedbackExamples: feedbackExamples)

        switch self {
        case .ollama:
            let configuration = settings.ollama
            let baseURL = try validatedBaseURL(from: configuration)
            guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OllamaError.missingModel
            }

            var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(configuration.timeoutSeconds, 10))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                OllamaGenerateRequest(
                    model: configuration.modelName,
                    prompt: prompt,
                    stream: false,
                    format: nil
                )
            )

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            return try parseLearningMemory(from: response.response, sourceFeedbackCount: feedbackExamples.count)
        case .codex, .claude:
            let run = try ChatCLIReviewRunner.runStructuredJSON(
                tool: chatCLITool,
                prompt: prompt,
                schemaJSON: structuredOutputSchemaJSON(for: .learningMemory),
                model: configuredCLIModel(from: settings.chatCLI),
                timeoutSeconds: settings.chatCLI.timeoutSeconds
            )
            return try parseLearningMemory(from: run.output, sourceFeedbackCount: feedbackExamples.count)
        }
    }

    func generateFocusGuardNudge(
        settings: CaptureSettings,
        goal: String,
        assessmentReason: String,
        driftLabels: [String],
        matchedLabels: [String],
        events: [ActivityEvent]
    ) async throws -> String {
        let prompt = focusGuardNudgePrompt(
            goal: goal,
            assessmentReason: assessmentReason,
            driftLabels: driftLabels,
            matchedLabels: matchedLabels,
            events: events
        )

        switch self {
        case .ollama:
            let configuration = settings.ollama
            let baseURL = try validatedBaseURL(from: configuration)
            guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OllamaError.missingModel
            }

            var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(min(max(configuration.timeoutSeconds, 10), 20))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                OllamaGenerateRequest(
                    model: configuration.modelName,
                    prompt: prompt,
                    stream: false,
                    format: nil
                )
            )

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            return try parseFocusGuardNudge(from: response.response)
        case .codex, .claude:
            let run = try ChatCLIReviewRunner.runPlainText(
                tool: chatCLITool,
                prompt: prompt,
                model: configuredCLIModel(from: settings.chatCLI),
                timeoutSeconds: min(max(settings.chatCLI.timeoutSeconds, 10), 20)
            )
            return try parseFocusGuardNudge(from: run.output)
        }
    }

    private func validatedBaseURL(from configuration: OllamaConfiguration) throws -> URL {
        guard let url = URL(string: configuration.baseURLString) else {
            throw OllamaError.invalidBaseURL
        }
        guard let host = url.host?.lowercased(), host == "127.0.0.1" || host == "localhost" else {
            throw OllamaError.remoteHostsForbidden
        }
        return url
    }

    private func generateOllamaReviewRun(
        configuration: OllamaConfiguration,
        baseURL: URL,
        prompt: String,
        title: String,
        personName: String?,
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) async throws -> LocalReviewRun {
        var raw = ""

        do {
            var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(max(configuration.timeoutSeconds, 10))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                OllamaGenerateRequest(
                    model: configuration.modelName,
                    prompt: prompt,
                    stream: false,
                    format: .jsonSchema(.sessionReview)
                )
            )

            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            raw = response.response.trimmingCharacters(in: .whitespacesAndNewlines)

            let review = try parseSessionReview(
                from: raw,
                title: title,
                personName: personName,
                startedAt: startedAt,
                endedAt: endedAt,
                events: events,
                segments: segments
            )
            return LocalReviewRun(
                providerTitle: "Ollama",
                prompt: prompt,
                rawResponse: raw,
                review: review
            )
        } catch {
            ReviewDebugLogger.logReviewFailure(
                sessionTitle: title,
                error: error.localizedDescription,
                prompt: prompt,
                rawResponse: raw
            )

            if let error = error as? OllamaError {
                throw error
            }
            throw OllamaError.invalidReview("The local model did not return valid structured review output.")
        }
    }

    private var chatCLITool: ChatCLITool {
        switch self {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .ollama:
            preconditionFailure("Ollama does not map to a chat CLI tool.")
        }
    }

    private func configuredCLIModel(from configuration: ChatCLIConfiguration) -> String? {
        switch self {
        case .codex:
            return configuration.codexModelName.trimmedOrNil
        case .claude:
            return configuration.claudeModelName.trimmedOrNil
        case .ollama:
            return nil
        }
    }

    private func parseSessionReview(
        from output: String,
        title: String,
        personName: String?,
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) throws -> SessionReview {
        let payload = try parseStructuredSessionReviewPayload(from: output)
        let headline = payload.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let insight = payload.insight.trimmingCharacters(in: .whitespacesAndNewlines)
        let observedSegments = TimelineDeriver.observeSegments(segments, goal: title)
        let observability = TimelineDeriver.summarizeObservedSegments(observedSegments)

        let goalMatch: SessionGoalMatch
        let quality: SessionQuality
        switch observability.goalProgressEstimate {
        case .strong:
            goalMatch = .strong
            quality = .coherent
        case .partial:
            goalMatch = .partial
            quality = .mixed
        case .weak, .none:
            goalMatch = .weak
            quality = observability.driftSeconds > 0 ? .drifted : .mixed
        }

        return SessionReview(
            sessionTitle: title,
            startedAt: startedAt,
            endedAt: endedAt,
            verdict: SessionVerdict(goalMatch: goalMatch),
            quality: quality,
            goalMatch: goalMatch,
            headline: headline,
            summary: body,
            summarySpans: [],
            why: body,
            interruptions: [],
            interruptionSpans: [],
            reasons: [insight],
            timeline: Array(segments.prefix(6)).map {
                SessionTimelineEntry(
                    at: ActivityFormatting.shortTime.string(from: $0.startAt),
                    text: [$0.primaryLabel, $0.secondaryLabel].compactMap { $0 }.joined(separator: " · "),
                    url: $0.url
                )
            },
            trace: [],
            evidence: .empty,
            links: [],
            appDurations: [],
            appSwitchCount: 0,
            repoName: segments.compactMap(\.repoName).first,
            nearbyEventTitle: nil,
            mediaSummary: nil,
            clipboardPreview: nil,
            dominantApps: Array(segments.map(\.appName).orderedUnique().prefix(4)),
            sessionPath: Array(segments.map(\.primaryLabel).orderedUnique().prefix(4)),
            breakPointAtLabel: nil,
            breakPoint: nil,
            dominantThread: nil,
            referenceURL: nil,
            focusAssessment: insight,
            confidenceNotes: [],
            segments: segments,
            attentionSegments: AttentionDeriver.derive(from: segments)
        )
    }

    private func sessionReviewPrompt(
        title: String,
        personName: String?,
        contextPattern: ContextPatternSnapshot?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment]
    ) -> String {
        let coreEvents = events.filter { !$0.kind.isFocusGuardSignal }
        let allowedMentions = allowedEvidenceMentions(from: segments, events: coreEvents)
        let factPack = sessionPromptFactPack(from: segments)
        let reviewStats = sessionReviewStats(from: segments)
        let promptTopApps = promptTopApps(from: coreEvents)
        let evidence = SessionEvidenceSummary(
            topApps: promptTopApps,
            topTitles: topCounts((coreEvents.compactMap(\.windowTitle) + coreEvents.compactMap(\.resourceTitle)).map(cleanedTitleLabel), limit: 8),
            topURLs: topCounts((coreEvents.compactMap(\.resourceURL) + coreEvents.compactMap(\.domain)).map(readableReviewLocationLabel), limit: 6),
            topPaths: topCounts((coreEvents.compactMap(\.path) + coreEvents.compactMap(\.workingDirectory)), limit: 6),
            commands: Array(coreEvents.compactMap(\.command).orderedUnique().prefix(8)),
            clipboardPreviews: Array(coreEvents.compactMap(\.clipboardPreview).orderedUnique().prefix(3)),
            quickNotes: Array(coreEvents.compactMap(\.noteText).orderedUnique().prefix(4)),
            trace: []
        )

        let segmentLines = segments.prefix(12).map { segment in
            let interval = ActivityFormatting.sessionTime.string(from: segment.startAt, to: segment.endAt)
            let descriptor = [segment.appName, segment.primaryLabel, segment.secondaryLabel].compactMap { $0 }.joined(separator: " · ")
            let details = [
                segment.repoName,
                segment.filePath,
                segment.domain,
            ].compactMap { $0 }.joined(separator: " | ")
            return "- \(interval): \(descriptor)\(details.isEmpty ? "" : " [\(details)]")"
        }.joined(separator: "\n")

        return """
        Write a sharp, human review of one desktop session from local evidence.
        Your job is to judge whether the block stayed aligned with the goal, not to narrate raw app usage.

        Return only one JSON object with exactly these keys:
        - headline
        - summary
        - insight

        Rules:
        - Use second person.
        - Never use the person's name.
        - Address the person directly as "you" or "your".
        - `headline` and `summary` must do different jobs.
        - Headline under 10 words and no colon.
        - `headline` must name what the block became, not just what app was open.
        - Do not use a bare activity phrase like "Watching YouTube videos" or "Using Chrome" as the headline.
        - Prefer calm judgment phrases like "This block shifted into...", "This session became...", "This stayed on...", or "This never really became..."
        - Write the headline the way a sharp human would actually say it out loud.
        - Prefer concrete, everyday wording like "repo work", "feed checking", "setup thrash", "tab hopping", "spec reading", or "video rabbit hole".
        - Avoid abstract or consultant-style nouns like "alignment", "orientation", "fragmentation", "coherence", "optimization", "reconnaissance", "exploration", or "context switching".
        - Do not turn the headline into a category label, framework label, or productivity diagnosis.
        - Do not use blamey or robotic phrases like "you got pulled into", "X took this block", "accounted for", or "you spent the session".
        - `summary` should usually be exactly two short sentences and stay under 50 words total.
        - Sentence 1 should say what mostly happened.
        - Sentence 2 should say what weakened it, or what still held if it mostly stayed on task.
        - `summary` must explain the session shape, not just restate timing facts.
        - `summary` must add concrete evidence that is not already stated in the headline.
        - `summary` must include:
          1. the dominant surface or app
          2. at least one numeric fact from the computed facts below
          3. one concrete title, page, or surface when available
          4. the work surface that lost, when it is visible
        - Treat app names as evidence, not as the answer.
        - Judge the session against the goal first. A browser, Codex, Cursor, YouTube, or X can all be on-goal if the visible work supports the goal.
        - Do not restate the headline with light paraphrasing.
        - `summary` renders directly in the UI. Do not output XML, HTML, app tags, link tags, code fences, JSON inside strings, or raw URLs.
        - Plain markdown is allowed, but use it lightly.
        - If the evidence supports it, include the dominant time split in minutes or percent.
        - If the dominant app or site is clear, name it plainly in the sentence.
        - If a specific video, page, or document title is visible in the evidence, include it plainly.
        - If the title is generic, missing, or redacted, do not guess.
        - If the same block includes both browser-shell facts and site facts, trust the site facts and ignore the browser shell.
        - Keep each sentence plain and direct. No semicolons, no em dashes, and no stacked clause chains.
        - Prefer one useful title or surface over a long list of apps.
        - Do not sound like a dashboard, analyst, or therapist.
        - Bad summary wording: "led with", "was dominant across", "surfaced for", "fragmented across", "accounted for", "remained the dominant surface".
        - `insight` must be exactly one sentence and under 18 words.
        - `insight` must be one calm next move or framing correction, not a scolding command.
        - `insight` must be actionable right away, not just observational.
        - Prefer a stop-and-replace rule or a reframing rule: stop one behavior and name the next surface or framing to use instead.
        - If the block drifted to YouTube, X, passive media, or unrelated browsing, `insight` should say what to cut or close next.
        - If the block partly matched the goal, `insight` should say what to keep and what to remove.
        - `insight` must move toward the stated goal, not deeper into the distraction.
        - Never tell the person to continue scrolling, watching, or browsing a distraction surface unless the goal explicitly asked for that same surface.
        - For vague goals, default the replacement action toward planning, coding, writing, or the visible work tool, not the distraction.
        - Good insight: "If Codex is the real task, name the next block around it."
        - Good insight: "Close YouTube and return to the repo thread in Codex."
        - Good insight: "Keep the research, but cut the feed hopping."
        - Good insight: "Restart this as a Codex block if that is the real work."
        - Bad insight: "Complete the X feed review first."
        - Bad insight: "Close YouTube before the next block."
        - Bad insight: "Maintain focus on your primary tasks."
        - Bad insight: "Refocus on the task in Codex."
        - Bad insight: "Return to your main goal."
        - Use short, plain English.
        - Mention only concrete things that appear in the evidence.
        - Mention at least one concrete app, site, or tool from the evidence in `summary` when one is available.
        - Prefer the most specific surface available: named page, feed, document, or video title first; then site; then app shell.
        - If a browser site like YouTube or X already explains the block, do not mention Chrome or Safari in the summary.
        - Mention Chrome or Safari only when no site, feed, page, or video label is available.
        - Avoid raw domain spellings like youtube.com or x.com in the answer. Use plain product names instead.
        - Prior pattern memory is soft context only. Use it to judge what is normal for this user, but never let it override the current-session facts.
        - `insight` must act on the same dominant distraction or winning surface already named in the headline or summary.
        - Do not introduce a new app or site in `insight` unless it clearly consumed more time than the named distraction.
        - Good `summary` example: "Codex held about 9 minutes, but Telegram and Zoom kept breaking the thread."
        - Good `summary` example: "Most of the block stayed on YouTube, mainly Taylor Swift interview clips. Codex only showed up in short checks."
        - Good `summary` example: "Most of the block stayed on YouTube, mainly Taylor Swift interview clips, while Codex only appeared briefly for about a minute."
        - Good `summary` example: "X held about 68% of the block, mostly on the Home feed, while Codex only showed up in short checks."
        - Bad `summary` example: "You spent the session primarily browsing social media."
        - Bad `summary` example: "The session involved content on several surfaces."
        - Bad `summary` example: "Codex led with about 9 minutes, 30% of the block, around Open Agents and related pages."
        - Bad `summary` example: "You stayed partly aligned while the block became fragmented repo orientation."
        - Keep `insight` plain text.
        - Do not output badges, extra keys, XML, code fences, or commentary outside the JSON object.
        - Do not mention instructions, examples, feedback machinery, scores, or hidden reasoning.
        - Judge the block against the stated goal, not generic productivity.
        - Do not classify by app name alone. A browser, YouTube, X, or Codex can be on-goal if the visited content supports the goal.
        - Treat the computed facts below as source of truth for timing, ordering, and dominance.
        - Use the goal plus the specific surfaces, titles, pages, and timing facts to decide what actually dominated the session.
        - If the goal is broad, describe the dominant thread instead of overselling success.
        - Never imply one app performed an action that happened on another site or surface.
        - If YouTube and Codex both appear, say which one dominated and how long each held the session.
        - If Driftly only appears as a quick app switch or review surface, keep it secondary.
        - If the session changed shape but still looks useful, say that plainly instead of forcing a distraction narrative.
        - If the evidence is mixed, say that plainly instead of pretending certainty.
        - Do not say "you spent the session", "accounted for", "main goal", "returning to your main goal", or "refocus on".
        - Never say "desktop activity", "during this time period", "desired focus work", "stated goal", or "lack of concentration".
        - Never say "fragmented repo orientation", "fragmented reconnaissance", "aligned exploration", "context switching spiral", or similar abstract rewrites.
        - Bad headline: "Watching YouTube videos"
        - Good headline: "This block shifted into YouTube"
        - Bad headline: "Session summary"
        - Good headline: "This session became feed checking"
        - Good headline: "This block stayed on the repo"
        - Good headline: "This became repo hopping"
        - Good headline: "This never really became repo study"
        - Good headline: "This mostly stayed on setup"
        - Bad headline: "This became fragmented repo orientation"
        - Bad headline: "This became aligned research exploration"
        - Bad headline: "This became productivity optimization"

        Goal: \(title)
        Time: \(ActivityFormatting.shortTime.string(from: startedAt)) to \(ActivityFormatting.shortTime.string(from: endedAt))

        Prior pattern memory from recent sessions:
        - Prior sessions considered: \(contextPattern?.sessionCount ?? 0)
        - Typical aligned surfaces:
        \(contextPattern?.alignedSurfaces.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Typical drift surfaces:
        \(contextPattern?.driftSurfaces.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Common switches:
        \(contextPattern?.commonTransitions.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        Earlier feedback hints:
        \(reviewLearnings.isEmpty ? "- none" : reviewLearnings.prefix(4).map { "- \($0)" }.joined(separator: "\n"))

        Session facts:
        - Total session length: \(naturalDurationLabel(for: reviewStats.totalSeconds))
        - Surface switches: \(reviewStats.switchCount)
        - Unique surfaces: \(reviewStats.uniqueSurfaceCount)
        - Dominant surface: \(reviewStats.dominantSurface ?? "none")
        - Dominant surface share: \(reviewStats.dominantSurfaceShare)
        - Longest continuous run: \(reviewStats.longestRunLabel ?? "none")
        - Top surfaces:
        \(reviewStats.topSurfaces.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Top apps:
        \(reviewStats.topApps.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Top page titles:
        \(reviewStats.topTitles.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Opening sequence:
        \(reviewStats.openingSequence.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        - Closing sequence:
        \(reviewStats.closingSequence.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        Visible media:
        \(factPack.visibleMedia.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        Visible sites:
        \(factPack.visibleSites.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        Brief interruptions:
        \(factPack.briefInterruptions.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

        Allowed mentions:
        \(allowedMentions.isEmpty ? "- none" : allowedMentions.map { "- \($0)" }.joined(separator: "\n"))

        Recent timeline:
        \(segmentLines.isEmpty ? "- none" : segmentLines)

        Evidence:
        - Apps: \(evidence.topApps.joined(separator: ", ").nilIfBlank ?? "none")
        - Titles: \(evidence.topTitles.joined(separator: " | ").nilIfBlank ?? "none")
        - URLs or domains: \(evidence.topURLs.joined(separator: " | ").nilIfBlank ?? "none")
        - Paths: \(evidence.topPaths.joined(separator: " | ").nilIfBlank ?? "none")
        - Commands: \(evidence.commands.joined(separator: " | ").nilIfBlank ?? "none")
        - Clipboard: \(evidence.clipboardPreviews.joined(separator: " | ").nilIfBlank ?? "none")
        - Notes: \(evidence.quickNotes.joined(separator: " | ").nilIfBlank ?? "none")
        """
    }
}

private func focusGuardNudgePrompt(
    goal: String,
    assessmentReason: String,
    driftLabels: [String],
    matchedLabels: [String],
    events: [ActivityEvent]
) -> String {
    let factPack = sessionPromptFactPack(from: TimelineDeriver.deriveSegments(from: events, sessionEnd: events.last?.occurredAt ?? Date()))
    let titles = topCounts((events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)).map(cleanedTitleLabel), limit: 4)
    let sites = topCounts((events.compactMap(\.domain) + events.compactMap(\.resourceURL)), limit: 4)

    return """
    Write one short Mac notification sentence for a focus app.

    Goal: \(goal)
    Drift surfaces: \(driftLabels.joined(separator: " | ").nilIfBlank ?? "none")
    Work surfaces: \(matchedLabels.joined(separator: " | ").nilIfBlank ?? "none")
    Assessment: \(assessmentReason)

    Visible media:
    \(factPack.visibleMedia.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

    Visible sites:
    \(factPack.visibleSites.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

    Recent titles:
    \(titles.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

    Recent sites:
    \(sites.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")

    Rules:
    - One sentence only.
    - Max 14 words.
    - Use second person.
    - Mention the distraction directly.
    - Point back to the goal or main work surface.
    - No motivational language.
    - No generic phrases like stay focused, maintain focus, primary tasks, or get back on track.
    - No colon. No quotes. No markdown.
    - Return only the sentence.

    Good: You drifted to YouTube. Back to the Codex block?
    Good: Gemini took over this block. Back to shipping in Codex?
    Bad: Maintain focus on your primary tasks.
    """
}

private func parseFocusGuardNudge(from output: String) throws -> String {
    let line = output
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        .map { String($0) }?
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ ").union(.whitespacesAndNewlines))
        ?? ""

    let cleaned = line
        .replacingOccurrences(of: #"\s+"#, with: " ", options: NSString.CompareOptions.regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

    guard !cleaned.isEmpty else {
        throw OllamaError.invalidReview("The local model returned an empty focus nudge.")
    }
    if let leakedPhrase = leakedPromptPhrase(in: [cleaned]) {
        throw OllamaError.invalidReview("The local model echoed nudge instructions (\(leakedPhrase)).")
    }
    if let invalidPhrase = invalidGenericReviewPhrase(in: [cleaned]) {
        throw OllamaError.invalidReview("The local model returned generic nudge copy (\(invalidPhrase)).")
    }
    guard cleaned.split(separator: " ").count <= 14 else {
        throw OllamaError.invalidReview("The local model returned a focus nudge that was too long.")
    }

    return cleaned
}

private func feedbackLearningPrompt(personName: String?, feedbackExamples: [SessionReviewFeedbackExample]) -> String {
    let block = feedbackExamples.map { example in
        """
        - Goal: \(example.goal)
          Review said: \(example.reviewSaid)
          User feedback: \(example.userFeedback)
          Label: \(example.label.rawValue)
        """
    }.joined(separator: "\n")

    return """
    <role>
    You are summarizing past feedback about session reviews for a local-only desktop focus app.
    The person's first name is \(personName?.nilIfBlank ?? "unknown"), but do not use their name in the output.
    </role>

    <output_contract>
    Return strict JSON with this shape only:
    {"learnings":["...", "..."]}
    </output_contract>

    <style_rules>
    - Write 3 to 6 learnings.
    - Each learning must be short.
    - Each learning must be user-specific review-framing guidance.
    - Do not mention session IDs.
    - Do not mention prompt instructions, model behavior, or internal tools.
    - Do not make claims stronger than the feedback supports.
    - Prefer guidance like "mention X when it happened" or "do not frame Y as drift by default".
    </style_rules>

    <feedback_examples>
    \(block.isEmpty ? "- none" : block)
    </feedback_examples>

    <task>
    Summarize the feedback examples into reusable guidance for how future session reviews should be framed for this person.
    Return only strict JSON.
    </task>
    """
}

private func allowedEvidenceMentions(
    from segments: [TimelineSegment],
    events: [ActivityEvent]
) -> [String] {
    var mentions: [String] = []
    var seen: Set<String> = []

    func append(_ value: String?) {
        guard let value else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
        mentions.append(trimmed)
    }

    for segment in segments {
        append(segment.appName)
        append(segment.primaryLabel)
        append(segment.secondaryLabel)
        append(segment.repoName)
        append(segment.domain)
        if let filePath = segment.filePath {
            append(URL(fileURLWithPath: filePath).lastPathComponent)
        }
    }

    for title in (events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)).prefix(16) {
        append(cleanedTitleLabel(title))
    }

    return Array(mentions.prefix(30))
}

private struct SessionPromptFactPack {
    let frontmostBreakdown: [String]
    let visibleMedia: [String]
    let visibleSites: [String]
    let briefInterruptions: [String]
    let backgroundContext: [String]
}

private struct SessionReviewStats {
    let totalSeconds: Int
    let switchCount: Int
    let uniqueSurfaceCount: Int
    let dominantSurface: String?
    let dominantSurfaceShare: String
    let longestRunLabel: String?
    let topSurfaces: [String]
    let topApps: [String]
    let topTitles: [String]
    let openingSequence: [String]
    let closingSequence: [String]
}

private func sessionReviewStats(from segments: [TimelineSegment]) -> SessionReviewStats {
    struct Aggregate {
        var label: String
        var seconds: Int
    }

    let totalSeconds = max(segments.reduce(0) { $0 + segmentDurationSeconds($1) }, 1)

    func aggregate(
        matching predicate: (TimelineSegment) -> Bool = { _ in true },
        label: (TimelineSegment) -> String,
        limit: Int
    ) -> [String] {
        var buckets: [String: Aggregate] = [:]

        for segment in segments where predicate(segment) {
            let rawLabel = label(segment).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLabel.isEmpty else { continue }
            var aggregate = buckets[rawLabel] ?? Aggregate(label: rawLabel, seconds: 0)
            aggregate.seconds += segmentDurationSeconds(segment)
            buckets[rawLabel] = aggregate
        }

        return buckets.values
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.seconds > rhs.seconds
            }
            .prefix(limit)
            .map { aggregate in
                let share = Int((Double(aggregate.seconds) / Double(totalSeconds) * 100).rounded())
                return "\(aggregate.label) — \(naturalDurationLabel(for: aggregate.seconds)) (\(share)%)"
            }
    }

    let topSurfaces = aggregate(
        label: { segment in
            if let secondary = segment.secondaryLabel, !secondary.isEmpty, secondary != segment.primaryLabel {
                return "\(segment.primaryLabel) · \(secondary)"
            }
            return segment.primaryLabel
        },
        limit: 4
    )

    let topApps = aggregate(
        matching: { segment in
            !isBrowserShellApp(segment.appName) || !segmentHasWebContext(segment)
        },
        label: \.appName,
        limit: 4
    )

    let topTitles = aggregate(
        matching: { ($0.secondaryLabel?.isEmpty == false) || ($0.domain?.isEmpty == false) },
        label: { segment in
            if let secondary = segment.secondaryLabel, !secondary.isEmpty {
                return secondary
            }
            return segment.primaryLabel
        },
        limit: 4
    )

    let dominantSurfaceAggregate = topSurfaces.first
    let dominantSurface = dominantSurfaceAggregate?.components(separatedBy: " — ").first
    let dominantSurfaceShare = dominantSurfaceAggregate?
        .components(separatedBy: " (")
        .last?
        .trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        ?? "0%"

    let longestSegment = segments.max { segmentDurationSeconds($0) < segmentDurationSeconds($1) }
    let longestRunLabel = longestSegment.map { segment in
        "\(segment.primaryLabel) for \(naturalDurationLabel(for: segmentDurationSeconds(segment)))"
    }

    func sequenceLine(for segment: TimelineSegment) -> String {
        let primary = segment.primaryLabel
        let secondary = segment.secondaryLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = [primary, secondary].compactMap { value in
            guard let value, !value.isEmpty, value != primary else { return nil }
            return value
        }.joined(separator: " · ")
        let label = descriptor.isEmpty ? primary : descriptor
        return "\(label) — \(naturalDurationLabel(for: segmentDurationSeconds(segment)))"
    }

    let openingSequence = Array(segments.prefix(3)).map { sequenceLine(for: $0) }
    let closingSequence = Array(segments.suffix(3)).map { sequenceLine(for: $0) }

    return SessionReviewStats(
        totalSeconds: totalSeconds,
        switchCount: max(segments.count - 1, 0),
        uniqueSurfaceCount: Set(segments.map { "\($0.appName)|\($0.primaryLabel)|\($0.secondaryLabel ?? "")" }).count,
        dominantSurface: dominantSurface,
        dominantSurfaceShare: dominantSurfaceShare,
        longestRunLabel: longestRunLabel,
        topSurfaces: topSurfaces,
        topApps: topApps,
        topTitles: topTitles,
        openingSequence: openingSequence,
        closingSequence: closingSequence
    )
}

private func segmentDurationSeconds(_ segment: TimelineSegment) -> Int {
    max(Int(segment.endAt.timeIntervalSince(segment.startAt).rounded()), 1)
}

private func promptTopApps(from events: [ActivityEvent]) -> [String] {
    let hasWebContext = events.contains { event in
        (event.domain?.isEmpty == false) || (event.resourceURL?.isEmpty == false)
    }

    let appNames = events.compactMap(\.appName).filter { appName in
        if hasWebContext && isBrowserShellApp(appName) {
            return false
        }
        return true
    }

    return topCounts(appNames, limit: 6)
}

private func sessionPromptFactPack(from segments: [TimelineSegment]) -> SessionPromptFactPack {
    struct Aggregate {
        var label: String
        var seconds: Int
    }

    func aggregate(
        matching predicate: (TimelineSegment) -> Bool,
        label: (TimelineSegment) -> String,
        limit: Int
    ) -> [String] {
        var buckets: [String: Aggregate] = [:]
        for segment in segments where predicate(segment) {
            let key = label(segment).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            var current = buckets[key] ?? Aggregate(label: key, seconds: 0)
            current.seconds += segmentDurationSeconds(segment)
            buckets[key] = current
        }

        return buckets.values
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.seconds > rhs.seconds
            }
            .prefix(limit)
            .map { "\($0.label) — \(naturalDurationLabel(for: $0.seconds))" }
    }

    let frontmostBreakdown = aggregate(
        matching: { _ in true },
        label: { segment in segment.primaryLabel == segment.appName ? segment.appName : segment.primaryLabel },
        limit: 4
    )

    let visibleMedia = aggregate(
        matching: { $0.category == .media || $0.appName.localizedCaseInsensitiveContains("spotify") },
        label: { segment in
            if segment.appName.localizedCaseInsensitiveContains("spotify"),
               segment.primaryLabel.lowercased() != "spotify" {
                return "\(segment.primaryLabel) on Spotify"
            }
            return segment.primaryLabel
        },
        limit: 3
    )

    let visibleSites = aggregate(
        matching: { ($0.domain?.isEmpty == false) || $0.secondaryLabel != nil },
        label: { segment in
            if let domain = segment.domain, !domain.isEmpty {
                return "\(segment.primaryLabel) on \(domain)"
            }
            if let secondary = segment.secondaryLabel, !secondary.isEmpty {
                return "\(secondary) in \(segment.primaryLabel)"
            }
            return segment.primaryLabel
        },
        limit: 4
    )

    let briefInterruptions = segments
        .filter { segmentDurationSeconds($0) <= 30 }
        .map { segment in
            let label = segment.primaryLabel == segment.appName ? segment.appName : segment.primaryLabel
            return "\(label) — \(naturalDurationLabel(for: segmentDurationSeconds(segment)))"
        }
        .orderedUnique()
        .prefix(4)
        .map { $0 }

    let backgroundContext = segments
        .filter { $0.category == .media || $0.category == .social }
        .map { segment in
            if segment.appName.localizedCaseInsensitiveContains("spotify"),
               segment.primaryLabel.lowercased() != "spotify" {
                return "\(segment.primaryLabel) was visible in Spotify"
            }
            return "\(segment.primaryLabel) was visible"
        }
        .orderedUnique()
        .prefix(3)
        .map { $0 }

    return SessionPromptFactPack(
        frontmostBreakdown: frontmostBreakdown,
        visibleMedia: visibleMedia,
        visibleSites: visibleSites,
        briefInterruptions: Array(briefInterruptions),
        backgroundContext: Array(backgroundContext)
    )
}

private func naturalDurationLabel(for seconds: Int) -> String {
    if seconds < 20 {
        return "a few seconds"
    }
    if seconds < 45 {
        return "about half a minute"
    }
    if seconds < 90 {
        return "under a minute"
    }
    if seconds < 150 {
        return "about 2 minutes"
    }
    if seconds < 210 {
        return "about 3 minutes"
    }

    let minutes = Int((Double(seconds) / 60.0).rounded())
    return "about \(max(minutes, 1)) minutes"
}

private func observedEntityLabel(for segment: TimelineSegment) -> String {
    let domain = (segment.domain ?? "").lowercased()

    if domain == "github.com" {
        return segment.secondaryLabel ?? "GitHub"
    }
    if domain == "youtube.com" || domain == "youtu.be" {
        if let secondary = segment.secondaryLabel, !secondary.isEmpty {
            return "\(segment.primaryLabel): \(secondary)"
        }
        return segment.primaryLabel
    }
    if domain.contains("calendar.notion.so") {
        return segment.secondaryLabel.map { "Notion Calendar: \($0)" } ?? "Notion Calendar"
    }
    if domain == "x.com" || domain == "twitter.com" {
        return segment.secondaryLabel.map { "X: \($0)" } ?? "X"
    }
    if segment.appName.lowercased().contains("spotify") {
        return segment.primaryLabel.lowercased() == "spotify" ? "Spotify" : "Spotify: \(segment.primaryLabel)"
    }
    if let filePath = segment.filePath {
        return URL(fileURLWithPath: filePath).lastPathComponent
    }
    if let repoName = segment.repoName, !repoName.isEmpty {
        return repoName
    }
    if segment.primaryLabel != segment.appName {
        return segment.secondaryLabel.map { "\(segment.primaryLabel): \($0)" } ?? segment.primaryLabel
    }
    return segment.appName
}

enum OllamaError: LocalizedError {
    case invalidBaseURL
    case remoteHostsForbidden
    case missingModel
    case invalidReview(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Ollama base URL is invalid."
        case .remoteHostsForbidden:
            return "Only local Ollama hosts are allowed. Use localhost or 127.0.0.1."
        case .missingModel:
            return "Select an Ollama model in Settings before generating reviews."
        case let .invalidReview(message):
            return message
        }
    }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let size: Int64?
    }

    let models: [Model]
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: OllamaResponseFormat?
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private enum OllamaResponseFormat: Encodable {
    case json
    case jsonSchema(OllamaJSONSchema)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .json:
            try container.encode("json")
        case let .jsonSchema(schema):
            try container.encode(schema)
        }
    }
}

private enum JSONSchemaType: String, Encodable {
    case object
    case array
    case string
}

private struct OllamaJSONSchema: Encodable {
    let type: JSONSchemaType
    let properties: [String: OllamaJSONSchemaProperty]
    let required: [String]
    let additionalProperties: Bool

    static let sessionReview = OllamaJSONSchema(
        type: .object,
        properties: [
            "headline": OllamaJSONSchemaProperty(
                type: .string,
                description: "Short judgment about what the block became. Under 10 words."
            ),
            "summary": OllamaJSONSchemaProperty(
                type: .string,
                description: "Plain text interpretation of how the session compared with the goal, using concrete evidence. Under 48 words."
            ),
            "insight": OllamaJSONSchemaProperty(
                type: .string,
                description: "One calm, specific next move or reframing sentence that helps correct or continue the work."
            ),
        ],
        required: ["headline", "summary", "insight"],
        additionalProperties: false
    )

    static let learningMemory = OllamaJSONSchema(
        type: .object,
        properties: [
            "learnings": OllamaJSONSchemaProperty(
                type: .array,
                description: "Short user-specific review framing rules.",
                items: OllamaJSONSchemaProperty(type: .string)
            ),
        ],
        required: ["learnings"],
        additionalProperties: false
    )
}

private final class OllamaJSONSchemaProperty: Encodable {
    let type: JSONSchemaType
    let description: String?
    let properties: [String: OllamaJSONSchemaProperty]?
    let items: OllamaJSONSchemaProperty?
    let required: [String]?
    let additionalProperties: Bool?
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case items
        case required
        case additionalProperties
        case enumValues = "enum"
    }

    init(
        type: JSONSchemaType,
        description: String? = nil,
        properties: [String: OllamaJSONSchemaProperty]? = nil,
        items: OllamaJSONSchemaProperty? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.items = items
        self.required = required
        self.additionalProperties = additionalProperties
        self.enumValues = enumValues
    }
}

private struct StructuredSessionReviewPayload: Decodable {
    let headline: String
    let summary: String
    let insight: String

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case insight
    }
}

private enum StructuredOutputKind {
    case sessionReview
    case learningMemory
}

private func structuredOutputSchemaJSON(for kind: StructuredOutputKind) -> String {
    let schema: OllamaJSONSchema
    switch kind {
    case .sessionReview:
        schema = .sessionReview
    case .learningMemory:
        schema = .learningMemory
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(schema)
        guard let json = String(data: data, encoding: .utf8) else {
            preconditionFailure("Failed to encode structured output schema as UTF-8.")
        }
        return json
    } catch {
        preconditionFailure("Failed to encode structured output schema: \(error)")
    }
}

private struct ParsedStructuredSessionReviewPayload {
    let headline: String
    let summary: String
    let insight: String
}

private func parseStructuredSessionReviewPayload(from text: String) throws -> ParsedStructuredSessionReviewPayload {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else {
        throw OllamaError.invalidReview("The local model did not return valid JSON.")
    }

    let jsonString = String(raw[start...end])
    let data = Data(jsonString.utf8)
    let payload = try JSONDecoder().decode(StructuredSessionReviewPayload.self, from: data)

    guard !payload.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw OllamaError.invalidReview("The local model returned an empty headline.")
    }
    guard !payload.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw OllamaError.invalidReview("The local model returned an empty summary.")
    }
    guard !payload.insight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw OllamaError.invalidReview("The local model returned an empty insight.")
    }

    return ParsedStructuredSessionReviewPayload(
        headline: payload.headline,
        summary: payload.summary,
        insight: payload.insight
    )
}

private struct LearningMemoryPayload: Decodable {
    let learnings: [String]
}

private func parseLearningMemory(from text: String, sourceFeedbackCount: Int) throws -> SessionReviewLearningMemory {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else {
        throw SessionStoreError.sqlite(message: "The learning summary did not return valid JSON.")
    }

    let jsonString = String(raw[start...end])
    let data = Data(jsonString.utf8)
    let payload = try JSONDecoder().decode(LearningMemoryPayload.self, from: data)
    let learnings = payload.learnings
        .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return SessionReviewLearningMemory(
        sourceFeedbackCount: sourceFeedbackCount,
        learnings: Array(learnings.prefix(6))
    )
}

private func leakedPromptPhrase(in values: [String]) -> String? {
    let leakagePhrases = [
        "four required lines",
        "required lines",
        "derived facts",
        "raw evidence",
        "output contract",
        "review_learnings",
        "review learnings",
        "review_feedback_examples",
        "review feedback examples",
        "weak framing hints",
        "framing hints",
        "feedback notes",
        "earlier feedback examples",
        "session signals",
        "captured evidence",
        "allowed mentions",
        "allowed entity tags",
        "allowed entity refs",
        "guided writing",
        "actually mattered",
        "actual matters",
    ]

    for value in values {
        let lowered = value.lowercased()
        for phrase in leakagePhrases where lowered.contains(phrase) {
            return phrase
        }
    }

    return nil
}

private func invalidGenericReviewPhrase(in values: [String]) -> String? {
    let blockedPhrases = [
        "desktop activity",
        "during this time period",
        "desired focus work",
        "stated goal",
        "lack of concentration",
        "attention was diverted",
        "did not align with the stated goal",
        "was observed",
        "maintain focus on your primary tasks",
        "maintain focus on primary tasks",
        "minimize external media consumption",
        "stay focused on your main task",
        "avoid switching to other surfaces",
        "maintain focus on your main application",
    ]

    for value in values {
        let lowered = value.lowercased()
        for phrase in blockedPhrases where lowered.contains(phrase) {
            return phrase
        }
    }

    return nil
}

private func topCounts(_ values: [String], limit: Int) -> [String] {
    Dictionary(values.map { ($0.trimmingCharacters(in: .whitespacesAndNewlines), 1) }, uniquingKeysWith: +)
        .filter { !$0.key.isEmpty }
        .sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        .prefix(limit)
        .map(\.key)
}

private extension String {
    func trimmedOrFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func inferredRichSpans(from text: String, goal: String) -> [SessionReviewInlineSpan] {
    inferredRichSpans(from: text, goal: goal, segments: [])
}

private func inferredRichSpans(from text: String, goal: String, segments: [TimelineSegment]) -> [SessionReviewInlineSpan] {
    let quotedSegments = splitQuotedSegments(in: text)
    var spans: [SessionReviewInlineSpan] = []
    var usedEntityRefs: Set<String> = []

    for segment in quotedSegments {
        if segment.isQuoted {
            let cleaned = cleanedTitleLabel(segment.text)
            if !cleaned.isEmpty {
                spans.append(
                    SessionReviewInlineSpan(
                        kind: .title,
                        text: cleaned,
                        url: inferredURL(forTitle: cleaned, in: segments)
                    )
                )
            }
            continue
        }

        spans.append(
            contentsOf: inferredPlainSpans(
                from: segment.text,
                goal: goal,
                segments: segments,
                usedEntityRefs: &usedEntityRefs
            )
        )
    }

    return compactedRichSpans(spans)
}

private func inferredPlainSpans(
    from text: String,
    goal: String,
    segments: [TimelineSegment],
    usedEntityRefs: inout Set<String>
) -> [SessionReviewInlineSpan] {
    struct Match {
        let range: Range<String.Index>
        let span: SessionReviewInlineSpan
        let ref: String?
    }

    let entityPatterns = ReviewEntityRegistry.inferredEntityPatterns()

    var matches: [Match] = []

    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedGoal.isEmpty,
       let range = text.range(of: trimmedGoal, options: [.caseInsensitive]) {
        matches.append(
            Match(
                range: range,
                span: SessionReviewInlineSpan(kind: .goal, text: text[range].description),
                ref: "goal"
            )
        )
    }

    for pattern in entityPatterns {
        if usedEntityRefs.contains(pattern.referenceID) { continue }
        if let range = text.range(of: pattern.label, options: [.caseInsensitive]) {
            matches.append(
                Match(
                    range: range,
                    span: SessionReviewInlineSpan(
                        kind: .entity,
                        text: text[range].description,
                        entityKind: pattern.kind.rawValue,
                        referenceID: pattern.referenceID,
                        url: inferredURL(forReferenceID: pattern.referenceID, text: text[range].description, in: segments)
                    ),
                    ref: pattern.referenceID
                )
            )
        }
    }

    matches.sort { lhs, rhs in
        if lhs.range.lowerBound == rhs.range.lowerBound {
            return text.distance(from: lhs.range.lowerBound, to: lhs.range.upperBound) >
                text.distance(from: rhs.range.lowerBound, to: rhs.range.upperBound)
        }
        return lhs.range.lowerBound < rhs.range.lowerBound
    }

    var resolved: [Match] = []
    var lastUpperBound = text.startIndex
    for match in matches {
        if match.range.lowerBound < lastUpperBound { continue }
        resolved.append(match)
        lastUpperBound = match.range.upperBound
        if let ref = match.ref {
            usedEntityRefs.insert(ref)
        }
    }

    guard !resolved.isEmpty else {
        return [SessionReviewInlineSpan(kind: .text, text: text)]
    }

    var spans: [SessionReviewInlineSpan] = []
    var cursor = text.startIndex

    for match in resolved {
        if cursor < match.range.lowerBound {
            spans.append(SessionReviewInlineSpan(kind: .text, text: String(text[cursor..<match.range.lowerBound])))
        }
        spans.append(match.span)
        cursor = match.range.upperBound
    }

    if cursor < text.endIndex {
        spans.append(SessionReviewInlineSpan(kind: .text, text: String(text[cursor...])))
    }

    return spans
}

private func compactedRichSpans(_ spans: [SessionReviewInlineSpan]) -> [SessionReviewInlineSpan] {
    var result: [SessionReviewInlineSpan] = []

    for span in spans {
        let trimmed = span.kind == .text ? span.text : span.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }

        if span.kind == .text,
           let last = result.last,
           last.kind == .text {
            let merged = last.text + trimmed
            result[result.count - 1] = SessionReviewInlineSpan(kind: .text, text: merged)
        } else if span.kind == .text {
            result.append(SessionReviewInlineSpan(kind: .text, text: trimmed))
        } else {
            result.append(
                SessionReviewInlineSpan(
                    kind: span.kind,
                    text: trimmed,
                    entityKind: span.entityKind,
                    referenceID: span.referenceID,
                    url: span.url
                )
            )
        }
    }

    return result
}

private func normalizedInlineTagSpacing(_ spans: [SessionReviewInlineSpan]) -> [SessionReviewInlineSpan] {
    guard !spans.isEmpty else { return spans }

    var normalized = spans

    for index in normalized.indices {
        guard normalized[index].kind != .text else { continue }

        if index > normalized.startIndex, normalized[index - 1].kind == .text {
            let previousText = normalized[index - 1].text
            if let last = previousText.last, shouldInsertSpaceBeforeInlineTag(after: last) {
                normalized[index - 1] = SessionReviewInlineSpan(
                    kind: .text,
                    text: previousText + " "
                )
            }
        }

        if index < normalized.index(before: normalized.endIndex), normalized[index + 1].kind == .text {
            let nextText = normalized[index + 1].text
            if let first = nextText.first, shouldInsertSpaceAfterInlineTag(before: first) {
                normalized[index + 1] = SessionReviewInlineSpan(
                    kind: .text,
                    text: " " + nextText
                )
            }
        }
    }

    return compactedRichSpans(normalized)
}

private func shouldInsertSpaceBeforeInlineTag(after character: Character) -> Bool {
    if character.isWhitespace { return false }
    if character.isLetter || character.isNumber { return true }
    return false
}

private func shouldInsertSpaceAfterInlineTag(before character: Character) -> Bool {
    if character.isWhitespace { return false }
    if character.isLetter || character.isNumber { return true }
    return false
}

private func inferredURL(forReferenceID referenceID: String, text: String, in segments: [TimelineSegment]) -> String? {
    let definitionDomains = ReviewEntityRegistry.definition(forReferenceID: referenceID)?.domains ?? []

    switch referenceID {
    case "youtube":
        return preferredURL(
            in: segments,
            primaryDomainMatches: definitionDomains,
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.primaryLabel) == normalizedReviewLabel(text)
            }
        )
    case "github":
        return preferredURL(
            in: segments,
            primaryDomainMatches: definitionDomains,
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.repoName) == normalizedReviewLabel(text)
            }
        )
    case "x":
        return preferredURL(in: segments, primaryDomainMatches: definitionDomains)
    case "notion-calendar":
        return preferredURL(
            in: segments,
            primaryDomainMatches: definitionDomains,
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.primaryLabel) == normalizedReviewLabel(text)
            }
        )
    default:
        guard !definitionDomains.isEmpty else { return nil }
        return preferredURL(in: segments, primaryDomainMatches: definitionDomains)
    }
}

private func inferredURL(forTitle title: String, in segments: [TimelineSegment]) -> String? {
    preferredURL(
        in: segments,
        primaryDomainMatches: [],
        prefer: { segment in
            let normalizedTitle = normalizedReviewLabel(title)
            return normalizedReviewLabel(segment.secondaryLabel) == normalizedTitle ||
                normalizedReviewLabel(segment.primaryLabel) == normalizedTitle ||
                normalizedReviewLabel(cleanedTitleLabel(segment.secondaryLabel ?? "")) == normalizedTitle ||
                normalizedReviewLabel(cleanedTitleLabel(segment.primaryLabel)) == normalizedTitle
        }
    )
}

private func preferredURL(
    in segments: [TimelineSegment],
    primaryDomainMatches: [String],
    prefer: ((TimelineSegment) -> Bool)? = nil
) -> String? {
    let usableSegments = segments.filter { segment in
        guard let url = segment.url, !url.isEmpty else { return false }
        if primaryDomainMatches.isEmpty { return true }
        let domain = (segment.domain ?? "").lowercased()
        return primaryDomainMatches.contains(domain)
    }

    if let prefer, let exact = usableSegments.first(where: prefer) {
        return exact.url
    }

    return usableSegments.first?.url
}

private func normalizedReviewLabel(_ value: String?) -> String {
    guard let value else { return "" }
    return cleanedTitleLabel(value)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func readableReviewLocationLabel(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    if let components = URLComponents(string: trimmed), let host = components.host?.lowercased() {
        return readableReviewLocationLabel(
            host: host.replacingOccurrences(of: "www.", with: ""),
            path: components.path
        )
    }

    let lowered = trimmed.lowercased().replacingOccurrences(of: "www.", with: "")
    return readableReviewLocationLabel(host: lowered, path: "")
}

private func readableReviewLocationLabel(host: String, path: String) -> String {
    switch host {
    case "youtube.com", "youtu.be":
        if path.contains("/shorts") {
            return "YouTube Shorts"
        }
        if path.contains("/watch") {
            return "YouTube Watch"
        }
        return "YouTube"
    case "x.com", "twitter.com":
        if path == "/home" || path.isEmpty {
            return "X Home feed"
        }
        return "X"
    case "github.com":
        return "GitHub"
    case "mail.google.com":
        return "Gmail"
    case "docs.google.com":
        return "Google Docs"
    case "drive.google.com":
        return "Google Drive"
    case "calendar.google.com":
        return "Google Calendar"
    case "calendar.notion.so":
        return "Notion Calendar"
    case "notion.so", "notion.site":
        return "Notion"
    default:
        let root = host.split(separator: ".").first.map(String.init) ?? host
        let words = root
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { chunk in
                let value = String(chunk)
                return value.prefix(1).uppercased() + value.dropFirst()
            }
        return words.joined(separator: " ")
    }
}

private func isBrowserShellApp(_ appName: String) -> Bool {
    let lowered = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return [
        "google chrome",
        "chrome",
        "safari",
        "arc",
        "brave browser",
        "brave",
        "firefox"
    ].contains(lowered)
}

private func segmentHasWebContext(_ segment: TimelineSegment) -> Bool {
    (segment.domain?.isEmpty == false) || (segment.url?.isEmpty == false)
}

private func cleanedTitleLabel(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let suffixes = [
        " - YouTube",
        " – YouTube",
        " - Spotify",
        " – Spotify",
        " - Google Chrome",
        " – Google Chrome",
        " - Safari",
        " – Safari",
    ]

    for suffix in suffixes where value.hasSuffix(suffix) {
        value.removeLast(suffix.count)
        break
    }

    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func splitQuotedSegments(in text: String) -> [(text: String, isQuoted: Bool)] {
    let quotePairs: [Character: Character] = [
        "\"": "\"",
        "“": "”",
        "‘": "’",
    ]

    var segments: [(text: String, isQuoted: Bool)] = []
    var cursor = text.startIndex

    while cursor < text.endIndex {
        guard let quoteStart = text[cursor...].firstIndex(where: { quotePairs[$0] != nil }),
              let closingCharacter = quotePairs[text[quoteStart]],
              let quoteEnd = text[text.index(after: quoteStart)...].firstIndex(of: closingCharacter) else {
            segments.append((String(text[cursor...]), false))
            break
        }

        if cursor < quoteStart {
            segments.append((String(text[cursor..<quoteStart]), false))
        }

        let innerStart = text.index(after: quoteStart)
        if innerStart < quoteEnd {
            segments.append((String(text[innerStart..<quoteEnd]), true))
        }

        cursor = text.index(after: quoteEnd)
    }

    return segments
}

private extension Array where Element == String {
    func cleaned(limit: Int) -> [String] {
        Array(
            self
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .orderedUnique()
                .prefix(limit)
        )
    }

    var nonEmpty: [String]? {
        isEmpty ? nil : self
    }
}

private extension Sequence where Element: Hashable {
    func orderedUnique() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

import Foundation
import LogbookCore

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
    func availableModels(configuration: OllamaConfiguration) async throws -> [OllamaModel]
    func generateReview(
        configuration: OllamaConfiguration,
        title: String,
        personName: String?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment],
        calendarTitles: [String]
    ) async throws -> LocalReviewRun
    func summarizeLearningMemory(
        configuration: OllamaConfiguration,
        personName: String?,
        feedbackExamples: [SessionReviewFeedbackExample]
    ) async throws -> SessionReviewLearningMemory
}

enum AIProviderBridge: LocalReviewProvider {
    case ollama

    func availableModels(configuration: OllamaConfiguration) async throws -> [OllamaModel] {
        let endpoint = try validatedBaseURL(from: configuration).appending(path: "/api/tags")
        let (data, _) = try await URLSession.shared.data(from: endpoint)
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return response.models
            .map { OllamaModel(name: $0.name, sizeBytes: $0.size) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func generateReview(
        configuration: OllamaConfiguration,
        title: String,
        personName: String?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment],
        calendarTitles: [String]
    ) async throws -> LocalReviewRun {
        let baseURL = try validatedBaseURL(from: configuration)
        guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaError.missingModel
        }

        let prompt = sessionReviewPrompt(
            title: title,
            personName: personName,
            reviewLearnings: reviewLearnings,
            feedbackExamples: feedbackExamples,
            startedAt: startedAt,
            endedAt: endedAt,
            events: events,
            segments: segments,
            calendarTitles: calendarTitles
        )

        var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(configuration.timeoutSeconds, 10))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: configuration.modelName,
                prompt: prompt,
                stream: false
            )
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let raw = response.response.trimmingCharacters(in: .whitespacesAndNewlines)
        let review = try parseSessionReview(
            from: raw,
            title: title,
            personName: personName,
            startedAt: startedAt,
            endedAt: endedAt,
            segments: segments
        )
        return LocalReviewRun(
            providerTitle: "Ollama",
            prompt: prompt,
            rawResponse: raw,
            review: review
        )
    }

    func summarizeLearningMemory(
        configuration: OllamaConfiguration,
        personName: String?,
        feedbackExamples: [SessionReviewFeedbackExample]
    ) async throws -> SessionReviewLearningMemory {
        let baseURL = try validatedBaseURL(from: configuration)
        guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaError.missingModel
        }

        let prompt = feedbackLearningPrompt(personName: personName, feedbackExamples: feedbackExamples)

        var request = URLRequest(url: baseURL.appending(path: "/api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(configuration.timeoutSeconds, 10))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaGenerateRequest(
                model: configuration.modelName,
                prompt: prompt,
                stream: false
            )
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        return try parseLearningMemory(from: response.response, sourceFeedbackCount: feedbackExamples.count)
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

    private func parseSessionReview(
        from output: String,
        title: String,
        personName: String?,
        startedAt: Date,
        endedAt: Date,
        segments: [TimelineSegment]
    ) throws -> SessionReview {
        let payload = parsePlainTextReviewPayload(from: output)
        let normalizedHeadline = sanitizedReviewHeadline(
            normalizedReviewText(payload.headline, personName: personName),
            goal: title
        ).trimmedOrFallback("Session review ready.")
        let normalizedRecap = normalizedReviewText(payload.recap, personName: personName).trimmedOrFallback("The session completed with local evidence only.")
        let normalizedSummarySpans = inferredRichSpans(from: normalizedRecap, goal: title, segments: segments)
        let normalizedTakeaway = normalizedReviewText(payload.takeaway, personName: personName).trimmedOrFallback("The outcome stayed unclear.")
        return SessionReview(
            sessionTitle: title,
            startedAt: startedAt,
            endedAt: endedAt,
            verdict: payload.verdict,
            quality: payload.verdict == .matched ? .coherent : (payload.verdict == .missed ? .drifted : .mixed),
            goalMatch: payload.verdict == .matched ? .strong : (payload.verdict == .missed ? .weak : .partial),
            headline: normalizedHeadline,
            summary: normalizedRecap,
            summarySpans: normalizedSummarySpans,
            why: normalizedRecap,
            interruptions: [],
            interruptionSpans: [],
            reasons: [normalizedTakeaway],
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
            focusAssessment: normalizedTakeaway,
            confidenceNotes: [],
            segments: segments,
            attentionSegments: AttentionDeriver.derive(from: segments)
        )
    }

    private func sessionReviewPrompt(
        title: String,
        personName: String?,
        reviewLearnings: [String],
        feedbackExamples: [SessionReviewFeedbackExample],
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment],
        calendarTitles: [String]
    ) -> String {
        let intent = TimelineDeriver.deriveIntent(from: title)
        let observedSegments = TimelineDeriver.observeSegments(segments, goal: title)
        let observability = TimelineDeriver.summarizeObservedSegments(observedSegments)
        let goalSpecificity = goalSpecificityLabel(for: title, intent: intent)
        let directEntities = dominantObservedEntityLabels(from: observedSegments, role: .direct)
        let supportEntities = dominantObservedEntityLabels(from: observedSegments, role: .support)
        let driftEntities = dominantObservedEntityLabels(from: observedSegments, role: .drift)
        let breakEntities = dominantObservedEntityLabels(from: observedSegments, role: .breakTime)
        let allowedMentions = allowedEvidenceMentions(from: segments, events: events, calendarTitles: calendarTitles)
        let factPack = sessionPromptFactPack(from: segments)
        let evidence = SessionEvidenceSummary(
            topApps: topCounts(events.compactMap(\.appName), limit: 6),
            topTitles: topCounts((events.compactMap(\.windowTitle) + events.compactMap(\.resourceTitle)), limit: 8),
            topURLs: topCounts((events.compactMap(\.resourceURL) + events.compactMap(\.domain)), limit: 6),
            topPaths: topCounts((events.compactMap(\.path) + events.compactMap(\.workingDirectory)), limit: 6),
            commands: Array(events.compactMap(\.command).orderedUnique().prefix(8)),
            clipboardPreviews: Array(events.compactMap(\.clipboardPreview).orderedUnique().prefix(3)),
            quickNotes: Array(events.compactMap(\.noteText).orderedUnique().prefix(4)),
            calendarTitles: calendarTitles,
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

        let observedLines = observedSegments.prefix(12).map { observed in
            let segment = observed.segment
            let interval = ActivityFormatting.sessionTime.string(from: segment.startAt, to: segment.endAt)
            let descriptor = [segment.appName, segment.primaryLabel, segment.secondaryLabel].compactMap { $0 }.joined(separator: " · ")
            return "- \(interval): \(observed.role.rawValue) relevance=\(String(format: "%.2f", observed.goalRelevance)) \(descriptor) — \(observed.rationale)"
        }.joined(separator: "\n")

        return """
        <role>
        You are writing a short, useful session recap from local desktop evidence.
        Write like a perceptive friend who watched the block and is telling the person what actually happened.
        The person's first name is \(personName?.nilIfBlank ?? "unknown").
        </role>

        <output_contract>
        Return exactly four lines:
        VERDICT: matched|partially_matched|missed
        HEADLINE: ...
        RECAP: ...
        TAKEAWAY: ...
        </output_contract>

        <style_rules>
        - Use second person only.
        - Never say "the user", "they", or "\(personName?.nilIfBlank ?? "the person's") session".
        - Never use the person's name anywhere in the output.
        - Do not start the headline with "you,".
        - Do not start the headline with "This block", "During this session", or "You spent".
        - Do not use colons in the headline.
        - The headline should read like a short review title for this exact session, not a generic template.
        - The headline should name the dominant outcome, thread, or failure mode of the session.
        - Headline under 12 words.
        - RECAP under 48 words.
        - TAKEAWAY under 20 words.
        - Write at about an eighth-grade reading level.
        - Use short, plain sentences.
        - Every sentence should teach the reader something concrete.
        - Sound direct, specific, and human.
        - Do not use internal scoring language or classifier words.
        - Do not quote the goal text back unless it is essential.
        - Do not emit markdown, HTML, XML, bullets, or extra commentary.
        - Never mention any app, site, repo, file, video, song, page, or person unless it appears in the allowed mentions or raw evidence below.
        - You may use light markdown emphasis when helpful:
          - *italics* for titles like songs, videos, or page names
          - **bold** for a key point
          - `code` for repo names, file names, or paths
        - Use emphasis sparingly.
        </style_rules>

        <decision_rules>
        - Judge the block against the person's own intent, not generic productivity.
        - If the goal was to watch, browse, listen, or consume something, then doing that can count as matched.
        - If the goal was broad or fuzzy, do not pretend you know the real outcome. Say the outcome is unclear when needed.
        - For broad goals, prefer describing the dominant threads of the block over claiming success or failure.
        - Prefer what was actually viewed or worked on over the browser or app shell.
        - If a concrete title, repo, file, or page clearly mattered, mention it.
        - If the session bounced between tools without a clear artifact, say that plainly.
        - Name only things present in the evidence.
        - Avoid repeating the same app or site name multiple times.
        - Before answering, check that every concrete noun you mention is present in the evidence.
        - If music or media was visible, say what it was and about how long it stayed visible.
        - If a site or page was visible, say what it was and about how long it took.
        - If something only appeared briefly, call it brief.
        </decision_rules>

        <examples>
        <example>
        <input>
        goal: Help me get my day ready
        evidence: Codex, Spotify, WhatsApp, Log Book
        </input>
        <output>
        VERDICT: partially_matched
        HEADLINE: Setup time got split with music.
        RECAP: You spent about **2 minutes** in Codex, under a minute in Log Book, and almost **2 minutes** with Spotify visible, mostly on *BTS - 2.0*. WhatsApp interrupted the block briefly near the end.
        TAKEAWAY: You stayed near your setup tools, but the session never settled into a **clear day-prep run**.
        </output>
        </example>

        <example>
        <input>
        bad output pattern
        </input>
        <output>
        Bad: Aayush moved between work tools and media during preparation.
        Good: Work tools and media kept trading places.
        </output>
        </example>

        <example>
        <input>
        allowed mentions: Codex, Log Book, Spotify, WhatsApp
        </input>
        <output>
        Bad: YouTube took over the block.
        Good: You moved between Codex, Log Book, Spotify, and WhatsApp.
        </output>
        </example>

        <example>
        <input>
        goal: I wanna just watch YouTube
        evidence: YouTube watch page, one short X detour
        </input>
        <output>
        VERDICT: matched
        HEADLINE: YouTube stayed front and center.
        RECAP: You spent most of the block on YouTube and only dipped into X briefly.
        TAKEAWAY: The session **matched the goal**, with only a small detour.
        </output>
        </example>

        <example>
        <input>
        goal: deploy logbook to github
        evidence: Codex, GitHub auth/session pages, AayushMathur7/logbook, YouTube Shorts
        </input>
        <output>
        VERDICT: partially_matched
        HEADLINE: GitHub showed up, but YouTube won.
        RECAP: You reached GitHub and `AayushMathur7/logbook`, but YouTube still took more of the block than the deployment path did.
        TAKEAWAY: You did touch the task, but it never became the **main thread**.
        </output>
        </example>
        </examples>

        <review_learnings>
        These are weak hints learned from earlier feedback. They help with framing, but current session evidence always wins.
        \(reviewLearnings.isEmpty ? "- none" : reviewLearnings.prefix(6).map { "- \($0)" }.joined(separator: "\n"))
        </review_learnings>

        <review_feedback_examples>
        These are earlier examples of what the app said and how the person reacted.
        Use them as grounding references, not templates to copy.
        \(feedbackExamplesPromptBlock(feedbackExamples))
        </review_feedback_examples>

        <session>
        <goal>\(title)</goal>
        <time>\(ActivityFormatting.shortTime.string(from: startedAt)) to \(ActivityFormatting.shortTime.string(from: endedAt))</time>
        <goal_specificity>\(goalSpecificity)</goal_specificity>
        <intent>
        mode: \(intent.mode.rawValue)
        action: \(intent.action ?? "unknown")
        targets: \(intent.targets.joined(separator: " | ").nilIfBlank ?? "none")
        objects: \(intent.objects.joined(separator: " | ").nilIfBlank ?? "none")
        confidence: \(String(format: "%.2f", intent.confidence))
        </intent>

        <derived_facts>
        goal_related_time: \(shortDurationLabel(for: observability.directSeconds))
        nearby_time: \(shortDurationLabel(for: observability.supportSeconds))
        detour_time: \(shortDurationLabel(for: observability.driftSeconds))
        break_time: \(shortDurationLabel(for: observability.breakSeconds))
        longest_goal_related_run: \(shortDurationLabel(for: observability.longestDirectRunSeconds))
        detour_interruptions: \(observability.driftInterruptions)
        dominant_goal_related_entities: \(directEntities.joined(separator: " | ").nilIfBlank ?? "none")
        dominant_nearby_entities: \(supportEntities.joined(separator: " | ").nilIfBlank ?? "none")
        dominant_detours: \(driftEntities.joined(separator: " | ").nilIfBlank ?? "none")
        dominant_break_context: \(breakEntities.joined(separator: " | ").nilIfBlank ?? "none")
        frontmost_breakdown:
        \(factPack.frontmostBreakdown.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        visible_media:
        \(factPack.visibleMedia.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        visible_sites:
        \(factPack.visibleSites.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        brief_interruptions:
        \(factPack.briefInterruptions.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        likely_background_context:
        \(factPack.backgroundContext.map { "- \($0)" }.joined(separator: "\n").nilIfBlank ?? "- none")
        </derived_facts>

        <raw_timeline>
        \(segmentLines.isEmpty ? "- none" : segmentLines)
        </raw_timeline>

        <raw_observations>
        \(observedLines.isEmpty ? "- none" : observedLines)
        </raw_observations>

        <allowed_mentions>
        \(allowedMentions.isEmpty ? "- none" : allowedMentions.map { "- \($0)" }.joined(separator: "\n"))
        </allowed_mentions>

        <raw_evidence>
        apps: \(evidence.topApps.joined(separator: ", ").nilIfBlank ?? "none")
        titles: \(evidence.topTitles.joined(separator: " | ").nilIfBlank ?? "none")
        urls_or_domains: \(evidence.topURLs.joined(separator: " | ").nilIfBlank ?? "none")
        paths: \(evidence.topPaths.joined(separator: " | ").nilIfBlank ?? "none")
        commands: \(evidence.commands.joined(separator: " | ").nilIfBlank ?? "none")
        clipboard: \(evidence.clipboardPreviews.joined(separator: " | ").nilIfBlank ?? "none")
        quick_notes: \(evidence.quickNotes.joined(separator: " | ").nilIfBlank ?? "none")
        calendar: \(calendarTitles.joined(separator: " | ").nilIfBlank ?? "none")
        </raw_evidence>
        </session>

        <task>
        Write the four required lines using both the derived facts and the raw evidence.
        The derived facts are guidance, not a script. Use the raw evidence to decide what actually mattered.
        Use review_learnings as weak framing hints.
        Use review_feedback_examples as examples of what this person thought was right or wrong.
        Do not repeat old example wording unless it truly fits the current session.
        Do not let one old correction dominate the current session.
        HEADLINE should feel like the one-line title of the session review card.
        HEADLINE should be specific enough that someone could tell this session apart from another one.
        RECAP should explain what happened with concrete things and rough durations.
        TAKEAWAY should be one plain sentence about what the block adds up to.
        Return only the four required lines. Do not add anything before or after them.
        </task>
        """
    }
}

private func feedbackExamplesPromptBlock(_ examples: [SessionReviewFeedbackExample]) -> String {
    guard !examples.isEmpty else { return "- none" }

    return examples.map { example in
        """
        - Goal: \(example.goal)
          Review said: \(example.reviewSaid)
          User feedback: \(example.userFeedback)
          Label: \(example.label.rawValue)
        """
    }.joined(separator: "\n")
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

private func goalSpecificityLabel(for goal: String, intent: SessionIntent) -> String {
    let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if normalizedGoal.isEmpty || normalizedGoal == "work" || normalizedGoal == "stuff" || normalizedGoal == "be productive" {
        return "unclear"
    }

    if intent.mode == .unknown || intent.mode == .mixed {
        return intent.targets.isEmpty && intent.objects.isEmpty ? "unclear" : "broad"
    }

    let broadPhrases = [
        "get my day ready",
        "get ready",
        "get organized",
        "reset",
        "plan my day",
        "prepare my day",
        "day ready",
    ]

    if broadPhrases.contains(where: { normalizedGoal.contains($0) }) {
        return "broad"
    }

    if !intent.targets.isEmpty || !intent.objects.isEmpty {
        return "specific"
    }

    return "broad"
}

private func allowedEvidenceMentions(
    from segments: [TimelineSegment],
    events: [ActivityEvent],
    calendarTitles: [String]
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

    for calendarTitle in calendarTitles {
        append(calendarTitle)
    }

    return Array(mentions.prefix(30))
}

private func normalizedSecondPersonText(_ text: String) -> String {
    var value = text
    let replacements: [(String, String)] = [
        ("The user", "You"),
        ("the user", "you"),
        ("User", "You"),
        ("user", "you"),
        ("They ", "You "),
        ("they ", "you "),
        ("Their ", "Your "),
        ("their ", "your "),
        ("Them ", "You "),
        ("them ", "you "),
    ]

    for (source, target) in replacements {
        value = value.replacingOccurrences(of: source, with: target)
    }

    return value
}

private func normalizedReviewText(_ text: String, personName: String?) -> String {
    var value = normalizedSecondPersonText(text)

    if let personName = personName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !personName.isEmpty {
        let escapedName = NSRegularExpression.escapedPattern(for: personName)
        let patterns: [(String, String)] = [
            ("\\b\(escapedName)'s\\s+session\\b", "Your session"),
            ("\\b\(escapedName)'s\\b", "your"),
            ("\\b\(escapedName)\\b", "you"),
        ]

        for (pattern, replacement) in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: [.regularExpression, .caseInsensitive]
            )
        }
    }

    let genericReplacements: [(String, String)] = [
        ("\\bthe stated goal\\b", "what you meant to do"),
        ("\\blimited progress on what you meant to do\\b", "only partly matched what you meant to do"),
        ("\\blimited progress on the goal\\b", "only partly matched what you meant to do"),
        ("\\blimited progress toward the goal\\b", "only partly matched what you meant to do"),
        ("\\blimited progress towards the goal\\b", "only partly matched what you meant to do"),
    ]

    for (pattern, replacement) in genericReplacements {
        value = value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }

    let cleanupPatterns: [(String, String)] = [
        (#"^\s*you,\s*this block\b"#, "This block"),
        (#"^\s*you,\s*"#, "You "),
        (#"^\s*,+\s*"#, ""),
        (#"\n\s*,\s*\n"#, "\n"),
        (#"\s+([,.;:])"#, "$1"),
        (#"\s{2,}"#, " "),
    ]

    for (pattern, replacement) in cleanupPatterns {
        value = value.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression]
        )
    }

    if let first = value.first, String(first) == "y" {
        value.replaceSubrange(value.startIndex...value.startIndex, with: "Y")
    }

    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sanitizedReviewHeadline(_ text: String, goal: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)

    let timePrefixPattern = #"^\s*\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)\s*[-–—]\s*\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)\s*:?\s*"#
    value = value.replacingOccurrences(
        of: timePrefixPattern,
        with: "",
        options: .regularExpression
    )

    if value.hasSuffix(".") {
        value.removeLast()
    }

    let normalizedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedGoal.isEmpty,
       value.caseInsensitiveCompare(normalizedGoal) == .orderedSame {
        return "This block needs a clearer review."
    }

    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shortDurationLabel(for seconds: Int) -> String {
    if seconds <= 0 {
        return "0m"
    }

    if seconds < 60 {
        return "\(seconds)s"
    }

    let minutes = Int((Double(seconds) / 60.0).rounded())
    return "\(max(minutes, 1))m"
}

private struct SessionPromptFactPack {
    let frontmostBreakdown: [String]
    let visibleMedia: [String]
    let visibleSites: [String]
    let briefInterruptions: [String]
    let backgroundContext: [String]
}

private func sessionPromptFactPack(from segments: [TimelineSegment]) -> SessionPromptFactPack {
    struct Aggregate {
        var label: String
        var seconds: Int
    }

    func segmentSeconds(_ segment: TimelineSegment) -> Int {
        max(Int(segment.endAt.timeIntervalSince(segment.startAt).rounded()), 1)
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
            current.seconds += segmentSeconds(segment)
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
        .filter { segmentSeconds($0) <= 30 }
        .map { segment in
            let label = segment.primaryLabel == segment.appName ? segment.appName : segment.primaryLabel
            return "\(label) — \(naturalDurationLabel(for: segmentSeconds(segment)))"
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

private func dominantObservedEntityLabels(
    from observedSegments: [ObservedTimelineSegment],
    role: SessionSegmentRole,
    limit: Int = 3
) -> [String] {
    var seen: Set<String> = []
    var labels: [String] = []

    for observed in observedSegments where observed.role == role {
        let label = observedEntityLabel(for: observed.segment)
        guard !label.isEmpty, seen.insert(label).inserted else { continue }
        labels.append(label)
        if labels.count >= limit { break }
    }

    return labels
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

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The Ollama base URL is invalid."
        case .remoteHostsForbidden:
            return "Only local Ollama hosts are allowed. Use localhost or 127.0.0.1."
        case .missingModel:
            return "Select an Ollama model in Settings before generating reviews."
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
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct LocalSessionReviewPayload {
    let headline: String
    let verdict: SessionVerdict
    let recap: String
    let takeaway: String
}

private struct LearningMemoryPayload: Decodable {
    let learnings: [String]
}

private func parsePlainTextReviewPayload(from text: String) -> LocalSessionReviewPayload {
    let lines = text
        .split(whereSeparator: \.isNewline)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    var verdict: SessionVerdict?
    var headline: String?
    var recap: String?
    var takeaway: String?

    for line in lines {
        if line.uppercased().hasPrefix("VERDICT:") {
            let value = String(line.dropFirst("VERDICT:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            verdict = normalizedVerdict(from: value)
            continue
        }
        if line.uppercased().hasPrefix("HEADLINE:") {
            headline = String(line.dropFirst("HEADLINE:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        if line.uppercased().hasPrefix("RECAP:") {
            recap = String(line.dropFirst("RECAP:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
        if line.uppercased().hasPrefix("TAKEAWAY:") {
            takeaway = String(line.dropFirst("TAKEAWAY:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            continue
        }
    }

    let fallbackLines = lines.filter { line in
        let upper = line.uppercased()
        return !upper.hasPrefix("VERDICT:") && !upper.hasPrefix("HEADLINE:") && !upper.hasPrefix("RECAP:") && !upper.hasPrefix("TAKEAWAY:")
    }

    if headline == nil, let first = fallbackLines.first {
        headline = first
    }
    if recap == nil {
        recap = fallbackLines.count > 1 ? fallbackLines[1] : headline
    }
    if takeaway == nil {
        takeaway = fallbackLines.count > 2 ? fallbackLines[2] : recap
    }

    return LocalSessionReviewPayload(
        headline: headline?.trimmedOrFallback("Session review ready.") ?? "Session review ready.",
        verdict: verdict ?? inferredVerdict(from: [headline, recap, takeaway].compactMap { $0 }.joined(separator: " ")),
        recap: recap?.trimmedOrFallback("The session completed with local evidence only.") ?? "The session completed with local evidence only.",
        takeaway: takeaway?.trimmedOrFallback("The outcome stayed unclear.") ?? "The outcome stayed unclear."
    )
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

private func inferredVerdict(from text: String) -> SessionVerdict {
    let normalized = text.lowercased()
    if normalized.contains("mostly did what you meant to do")
        || normalized.contains("did what you meant to do")
        || normalized.contains("matched the goal")
        || normalized.contains("matched the intent") {
        return .matched
    }
    if normalized.contains("did not help")
        || normalized.contains("drift")
        || normalized.contains("took over")
        || normalized.contains("displaced")
        || normalized.contains("pulled away") {
        return .missed
    }
    return .partiallyMatched
}

private func normalizedVerdict(from value: String) -> SessionVerdict? {
    let normalized = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    switch normalized {
    case "matched", "match", "strong":
        return .matched
    case "partially_matched", "partial", "partially", "mixed":
        return .partiallyMatched
    case "missed", "miss", "weak", "failed":
        return .missed
    default:
        return SessionVerdict(rawValue: normalized)
    }
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

    let entityPatterns: [(label: String, kind: String, ref: String)] = [
        ("Notion Calendar", "site", "notion-calendar"),
        ("Google Docs", "site", "google-docs"),
        ("Google Drive", "site", "google-drive"),
        ("YouTube", "site", "youtube"),
        ("WhatsApp", "app", "whatsapp"),
        ("Safari", "app", "safari"),
        ("Chrome", "app", "chrome"),
        ("GitHub", "site", "github"),
        ("Spotify", "app", "spotify"),
        ("Notion", "site", "notion"),
        ("Cursor", "app", "cursor"),
        ("Codex", "app", "codex"),
        ("Log Book", "app", "log-book"),
        ("Logbook app", "app", "log-book"),
        ("Logbook", "app", "log-book"),
    ]

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
        if usedEntityRefs.contains(pattern.ref) { continue }
        if let range = text.range(of: pattern.label, options: [.caseInsensitive]) {
            matches.append(
                Match(
                    range: range,
                    span: SessionReviewInlineSpan(
                        kind: .entity,
                        text: text[range].description,
                        entityKind: pattern.kind,
                        referenceID: pattern.ref,
                        url: inferredURL(forReferenceID: pattern.ref, text: text[range].description, in: segments)
                    ),
                    ref: pattern.ref
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

private func inferredURL(forReferenceID referenceID: String, text: String, in segments: [TimelineSegment]) -> String? {
    switch referenceID {
    case "youtube":
        return preferredURL(
            in: segments,
            primaryDomainMatches: ["youtube.com", "youtu.be"],
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.primaryLabel) == normalizedReviewLabel(text)
            }
        )
    case "github":
        return preferredURL(
            in: segments,
            primaryDomainMatches: ["github.com"],
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.repoName) == normalizedReviewLabel(text)
            }
        )
    case "x":
        return preferredURL(in: segments, primaryDomainMatches: ["x.com", "twitter.com"])
    case "notion-calendar":
        return preferredURL(
            in: segments,
            primaryDomainMatches: ["calendar.notion.so"],
            prefer: { segment in
                normalizedReviewLabel(segment.secondaryLabel) == normalizedReviewLabel(text) ||
                normalizedReviewLabel(segment.primaryLabel) == normalizedReviewLabel(text)
            }
        )
    case "google-docs":
        return preferredURL(in: segments, primaryDomainMatches: ["docs.google.com"])
    case "google-drive":
        return preferredURL(in: segments, primaryDomainMatches: ["drive.google.com"])
    default:
        return nil
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

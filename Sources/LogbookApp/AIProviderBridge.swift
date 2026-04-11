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
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment],
        calendarTitles: [String]
    ) async throws -> LocalReviewRun
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
                format: "json",
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
        let jsonString = extractJSONObject(from: output)
        let payload = try decodeLocalSessionReviewPayload(from: jsonString)
        let normalizedHeadline = sanitizedReviewHeadline(
            normalizedReviewText(payload.headline, personName: personName),
            goal: title
        ).trimmedOrFallback("Session review ready.")
        let normalizedSummary = normalizedReviewText(payload.summary, personName: personName).trimmedOrFallback("The session completed with local evidence only.")
        let parsedSummarySpans = normalizedRichSpans(payload.summarySpans)
        let normalizedSummarySpans = parsedSummarySpans.isEmpty
            ? inferredRichSpans(from: normalizedSummary, goal: title)
            : parsedSummarySpans
        let normalizedInterruptions = payload.interruptions
            .map { normalizedReviewText($0, personName: personName) }
            .cleaned(limit: 3)
        let parsedInterruptionSpans = payload.interruptionSpans
            .prefix(3)
            .map(normalizedRichSpans)
        let normalizedInterruptionSpans = Array(normalizedInterruptions.enumerated()).map { index, interruption in
            if parsedInterruptionSpans.indices.contains(index), !parsedInterruptionSpans[index].isEmpty {
                return parsedInterruptionSpans[index]
            }
            return inferredRichSpans(from: interruption, goal: title)
        }
        let normalizedFocusAssessment = payload.focusAssessment.map { normalizedReviewText($0, personName: personName) }?.nilIfBlank
        let normalizedConfidenceNotes = payload.confidenceNotes
            .map { normalizedReviewText($0, personName: personName) }
            .cleaned(limit: 4)
        return SessionReview(
            sessionTitle: title,
            startedAt: startedAt,
            endedAt: endedAt,
            verdict: payload.verdict,
            quality: payload.verdict == .matched ? .coherent : (payload.verdict == .missed ? .drifted : .mixed),
            goalMatch: payload.verdict == .matched ? .strong : (payload.verdict == .missed ? .weak : .partial),
            headline: normalizedHeadline,
            summary: normalizedSummary,
            summarySpans: normalizedSummarySpans,
            why: normalizedSummary,
            interruptions: normalizedInterruptions,
            interruptionSpans: normalizedInterruptionSpans,
            reasons: normalizedConfidenceNotes.nonEmpty ?? [normalizedSummary],
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
            breakPointAtLabel: payload.keyMoments.first?.at,
            breakPoint: payload.interruptions.first,
            dominantThread: normalizedFocusAssessment,
            referenceURL: payload.keyMoments.compactMap(\.url).first,
            focusAssessment: normalizedFocusAssessment,
            confidenceNotes: normalizedConfidenceNotes,
            segments: segments,
            attentionSegments: AttentionDeriver.derive(from: segments)
        )
    }

    private func sessionReviewPrompt(
        title: String,
        personName: String?,
        startedAt: Date,
        endedAt: Date,
        events: [ActivityEvent],
        segments: [TimelineSegment],
        calendarTitles: [String]
    ) -> String {
        let intent = TimelineDeriver.deriveIntent(from: title)
        let observedSegments = TimelineDeriver.observeSegments(segments, goal: title)
        let observability = TimelineDeriver.summarizeObservedSegments(observedSegments)
        let directEntities = dominantObservedEntityLabels(from: observedSegments, role: .direct)
        let supportEntities = dominantObservedEntityLabels(from: observedSegments, role: .support)
        let driftEntities = dominantObservedEntityLabels(from: observedSegments, role: .drift)
        let breakEntities = dominantObservedEntityLabels(from: observedSegments, role: .breakTime)
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
        You are reviewing a completed session from local desktop evidence.
        Write like a sharp, calm friend describing what happened in one short recap.
        The person's first name is \(personName?.nilIfBlank ?? "unknown").

        Return valid JSON only with exactly this schema:
        {"headline":"...","verdict":"matched|partially_matched|missed","summary":"...","summary_spans":[{"type":"text|entity|title|goal|code|file","text":"...","entity_kind":"app|site|repo|file","ref":"optional-id"}],"interruptions":["..."],"interruptions_spans":[[{"type":"text|entity|title|goal|code|file","text":"...","entity_kind":"app|site|repo|file","ref":"optional-id"}]],"key_moments":[{"at":"h:mm a","text":"...","url":"https://..."}],"focus_assessment":"...","confidence_notes":["..."]}

        Rules:
        - headline under 18 words
        - summary under 45 words
        - be concrete and evidence-based
        - evaluate the session relative to the stated intent, not against a universal definition of productivity
        - speak directly to the person who did the session using second person
        - never say "the user", "user", or "they" when describing the session
        - default to "you"; do not narrate the person in third person and do not write phrases like "Aayush's session" or "their session"
        - you may use the person's first name at most once, and only as direct address like "Aayush, ..."
        - prefer the timeline over isolated raw events
        - the main question is: did this block materially help the stated goal or not
        - if the stated goal itself was to watch, browse, listen, or otherwise consume something, matching behavior can count as progress
        - YouTube, X, Spotify, GitHub, or any other surface are not inherently good or bad; judge them only relative to the stated intent
        - optimize for usefulness to the person reviewing the session, not for completeness
        - mention only evidence that helped the goal, hurt the goal, or changed the outcome
        - ignore neutral background context unless it clearly changed the session
        - treat aligned activity as the main thread of the goal, adjacent activity as nearby but indirect, off-path activity as detours, and breaks as intentional pauses
        - if adjacent activity dominated while aligned activity stayed low, say the block stayed near the goal but did not move it much
        - say plainly when the goal was displaced
        - never summarize behavior at the browser-shell level if a clearer viewed entity is known
        - avoid phrases like "in Google Chrome", "in Safari", or "exploring tabs" when you can name what was actually viewed
        - prefer "YouTube", "GitHub", "Notion Calendar", "Spotify", a repo, a file, or a specific page/title over the browser app name
        - confidence_notes should call out uncertainty only when needed
        - interruptions should be 0 to 3 items
        - interruptions should only include things that actually pulled the session away from the goal
        - do not include neutral tools or harmless context as interruptions
        - key_moments should be 3 to 6 factual anchors using session clock time
        - summary_spans and interruptions_spans must mirror the meaning of summary/interruptions
        - the writing should read naturally as prose first, not like a list of chips
        - use entity spans only for the most important apps, sites, repos, or files
        - use at most 2 entity spans in summary_spans unless a third is essential
        - do not repeat the same entity span more than once in the summary
        - when using entity spans, prefer these exact labels when they fit the evidence: YouTube, GitHub, Notion Calendar, Notion, Spotify, Safari, Chrome, X, Cursor, Codex, Google Docs, Google Drive
        - do not turn long page, video, or song titles into entity spans
        - use title spans for content titles like videos, pages, or songs
        - use title spans sparingly, usually 0 to 1 in the summary
        - use goal spans when directly naming the session goal
        - plain connective prose should remain text spans
        - if a service is obvious from context, mention it in plain text instead of another entity span
        - avoid badge spam such as YouTube, YouTube, YouTube repeated in one paragraph
        - prefer one good sentence over several fragmented clauses
        - summary should usually be a single sentence
        - long titles should be shortened to the most recognizable fragment
        - if an interruption bullet repeats the summary exactly, omit it
        - if the same service appears multiple times, collapse it into one mention and describe what pulled the block away
        - headline must be a judgment about goal progress, not a timestamp, not a session title, and not an app list
        - do not include clock times, date ranges, or colons in the headline
        - good headline examples: "You stayed near the work, but drift took over." / "You made progress on the UI, but not much." / "This block did not help the goal."
        - bad headline examples: "3:44 PM - 3:54 PM: YouTube Break instead of Logbook UI Work" / "YouTube, GitHub, Notion Calendar"
        - summary should answer three things in plain language: what helped, what got in the way, and whether the goal moved forward
        - if the goal barely moved, say that directly
        - for watch, listen, or browse goals, avoid phrases like "limited progress", "didn't move the goal forward", or "stated goal"; say whether the session matched the intent and mention detours plainly
        - when one specific video, song, page, repo, or file clearly dominated the block, mention it in the summary
        - never emit HTML or XML tags

        Good style example:
        summary: "You opened YouTube and watched sidemen clips instead of moving make me money forward."
        summary_spans: [
          {"type":"text","text":"You opened "},
          {"type":"entity","text":"YouTube","entity_kind":"site","ref":"youtube"},
          {"type":"text","text":" and watched "},
          {"type":"title","text":"sidemen clips"},
          {"type":"text","text":" instead of moving "},
          {"type":"goal","text":"make me money"},
          {"type":"text","text":" forward."}
        ]

        Bad style example:
        summary: "You opened YouTube and watched sidemen on YouTube and then another YouTube video on YouTube."

        Bad browser-shell example:
        summary: "You spent most of the session in Google Chrome, exploring tabs."

        Better browser-entity example:
        summary: "You stayed around the logbook repo at first, then drifted into YouTube while Spotify stayed active in the background."

        Better usefulness example:
        headline: "This block stayed near the goal, but didn’t move it much."
        summary: "You spent some of the block around Logbook UI work, but YouTube and short breaks absorbed enough time that the goal barely moved forward."
        interruptions: ["YouTube pulled a noticeable share of the block away from the UI work."]

        Intent-sensitive example:
        Session goal: I wanna just watch YouTube
        If the session mostly stayed on one YouTube watch page with only a short detour elsewhere, that should be matched or partially matched, not missed.

        Session goal: \(title)
        Session time: \(ActivityFormatting.shortTime.string(from: startedAt)) to \(ActivityFormatting.shortTime.string(from: endedAt))
        Derived intent:
        - mode: \(intent.mode.rawValue)
        - action: \(intent.action ?? "unknown")
        - targets: \(intent.targets.joined(separator: " | ").nilIfBlank ?? "none")
        - objects: \(intent.objects.joined(separator: " | ").nilIfBlank ?? "none")
        - confidence: \(String(format: "%.2f", intent.confidence))

        Derived session summary:
        - aligned activity: \(shortDurationLabel(for: observability.directSeconds))
        - adjacent activity: \(shortDurationLabel(for: observability.supportSeconds))
        - off-path activity: \(shortDurationLabel(for: observability.driftSeconds))
        - breaks: \(shortDurationLabel(for: observability.breakSeconds))
        - longest aligned run: \(shortDurationLabel(for: observability.longestDirectRunSeconds))
        - off-path interruptions: \(observability.driftInterruptions)
        - estimated goal progress: \(observability.goalProgressEstimate.rawValue)
        - dominant aligned entities: \(directEntities.joined(separator: " | ").nilIfBlank ?? "none")
        - dominant adjacent entities: \(supportEntities.joined(separator: " | ").nilIfBlank ?? "none")
        - dominant off-path entities: \(driftEntities.joined(separator: " | ").nilIfBlank ?? "none")
        - dominant break entities: \(breakEntities.joined(separator: " | ").nilIfBlank ?? "none")

        Timeline:
        \(segmentLines.isEmpty ? "- none" : segmentLines)

        Observed roles:
        \(observedLines.isEmpty ? "- none" : observedLines)

        Top apps: \(evidence.topApps.joined(separator: ", ").nilIfBlank ?? "none")
        Top titles: \(evidence.topTitles.joined(separator: " | ").nilIfBlank ?? "none")
        Top URLs/domains: \(evidence.topURLs.joined(separator: " | ").nilIfBlank ?? "none")
        Top paths: \(evidence.topPaths.joined(separator: " | ").nilIfBlank ?? "none")
        Commands: \(evidence.commands.joined(separator: " | ").nilIfBlank ?? "none")
        Clipboard: \(evidence.clipboardPreviews.joined(separator: " | ").nilIfBlank ?? "none")
        Quick notes: \(evidence.quickNotes.joined(separator: " | ").nilIfBlank ?? "none")
        Calendar: \(calendarTitles.joined(separator: " | ").nilIfBlank ?? "none")
        """
    }
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

    return value
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
    let format: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}

private struct LocalSessionReviewPayload: Decodable {
    struct InlineSpan: Decodable {
        let type: String
        let text: String
        let entityKind: String?
        let ref: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case entityKind = "entity_kind"
            case ref
        }
    }

    struct KeyMoment: Decodable {
        let at: String
        let text: String
        let url: String?
    }

    let headline: String
    let verdict: SessionVerdict
    let summary: String
    let summarySpans: [InlineSpan]
    let interruptions: [String]
    let interruptionSpans: [[InlineSpan]]
    let keyMoments: [KeyMoment]
    let focusAssessment: String?
    let confidenceNotes: [String]

    init(
        headline: String,
        verdict: SessionVerdict,
        summary: String,
        summarySpans: [InlineSpan] = [],
        interruptions: [String] = [],
        interruptionSpans: [[InlineSpan]] = [],
        keyMoments: [KeyMoment] = [],
        focusAssessment: String? = nil,
        confidenceNotes: [String] = []
    ) {
        self.headline = headline
        self.verdict = verdict
        self.summary = summary
        self.summarySpans = summarySpans
        self.interruptions = interruptions
        self.interruptionSpans = interruptionSpans
        self.keyMoments = keyMoments
        self.focusAssessment = focusAssessment
        self.confidenceNotes = confidenceNotes
    }

    enum CodingKeys: String, CodingKey {
        case headline
        case verdict
        case summary
        case summarySpans = "summary_spans"
        case interruptions
        case interruptionSpans = "interruptions_spans"
        case keyMoments = "key_moments"
        case focusAssessment = "focus_assessment"
        case confidenceNotes = "confidence_notes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decode(String.self, forKey: .headline)
        verdict = try container.decode(SessionVerdict.self, forKey: .verdict)
        summary = try container.decode(String.self, forKey: .summary)
        summarySpans = try container.decodeIfPresent([InlineSpan].self, forKey: .summarySpans) ?? []
        interruptions = try container.decodeIfPresent([String].self, forKey: .interruptions) ?? []
        interruptionSpans = try container.decodeIfPresent([[InlineSpan]].self, forKey: .interruptionSpans) ?? []
        keyMoments = try container.decodeIfPresent([KeyMoment].self, forKey: .keyMoments) ?? []
        focusAssessment = try container.decodeIfPresent(String.self, forKey: .focusAssessment)
        confidenceNotes = try container.decodeIfPresent([String].self, forKey: .confidenceNotes) ?? []
    }
}

private func extractJSONObject(from text: String) -> String {
    if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
        return String(text[start...end])
    }
    return text
}

private func decodeLocalSessionReviewPayload(from jsonString: String) throws -> LocalSessionReviewPayload {
    let data = Data(jsonString.utf8)
    if let payload = try? JSONDecoder().decode(LocalSessionReviewPayload.self, from: data) {
        return payload
    }

    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "Top-level review payload is not an object.")
        )
    }

    let headline = (dictionary["headline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let summary = (dictionary["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let verdict = normalizedVerdict(from: dictionary["verdict"]) ?? .partiallyMatched
    let summarySpans = parseInlineSpans(dictionary["summary_spans"])
    let interruptions = parseStringArray(dictionary["interruptions"], limit: 3)
    let interruptionSpans = parseInlineSpanGroups(dictionary["interruptions_spans"], limit: 3)
    let keyMoments = parseKeyMoments(dictionary["key_moments"], limit: 6)
    let focusAssessment = (dictionary["focus_assessment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let confidenceNotes = parseStringArray(dictionary["confidence_notes"], limit: 4)

    return LocalSessionReviewPayload(
        headline: headline.isEmpty ? "Session review ready." : headline,
        verdict: verdict,
        summary: summary.isEmpty ? "The session completed with local evidence only." : summary,
        summarySpans: summarySpans,
        interruptions: interruptions,
        interruptionSpans: interruptionSpans,
        keyMoments: keyMoments,
        focusAssessment: focusAssessment,
        confidenceNotes: confidenceNotes
    )
}

private func normalizedVerdict(from rawValue: Any?) -> SessionVerdict? {
    guard let value = rawValue as? String else { return nil }
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

private func parseStringArray(_ rawValue: Any?, limit: Int) -> [String] {
    if let strings = rawValue as? [String] {
        return Array(strings.prefix(limit))
    }
    if let string = rawValue as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }
    return []
}

private func parseInlineSpans(_ rawValue: Any?) -> [LocalSessionReviewPayload.InlineSpan] {
    guard let array = rawValue as? [[String: Any]] else { return [] }
    return array.compactMap { item in
        guard let type = item["type"] as? String, let text = item["text"] as? String else { return nil }
        return LocalSessionReviewPayload.InlineSpan(
            type: type,
            text: text,
            entityKind: item["entity_kind"] as? String,
            ref: item["ref"] as? String
        )
    }
}

private func parseInlineSpanGroups(_ rawValue: Any?, limit: Int) -> [[LocalSessionReviewPayload.InlineSpan]] {
    guard let groups = rawValue as? [Any] else { return [] }
    return Array(groups.prefix(limit)).compactMap { group in
        parseInlineSpans(group)
    }
}

private func parseKeyMoments(_ rawValue: Any?, limit: Int) -> [LocalSessionReviewPayload.KeyMoment] {
    guard let array = rawValue as? [[String: Any]] else { return [] }
    return Array(array.prefix(limit)).compactMap { item in
        guard let at = item["at"] as? String, let text = item["text"] as? String else { return nil }
        return LocalSessionReviewPayload.KeyMoment(
            at: at,
            text: text,
            url: item["url"] as? String
        )
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

private func normalizedRichSpans(_ spans: [LocalSessionReviewPayload.InlineSpan]) -> [SessionReviewInlineSpan] {
    spans.compactMap { span in
        let text = normalizedSecondPersonText(span.text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let kind: SessionReviewInlineSpan.Kind
        switch span.type.lowercased() {
        case "entity":
            kind = .entity
        case "title":
            kind = .title
        case "goal":
            kind = .goal
        case "code":
            kind = .code
        case "file":
            kind = .file
        default:
            kind = .text
        }

        return SessionReviewInlineSpan(
            kind: kind,
            text: text,
            entityKind: span.entityKind,
            referenceID: span.ref
        )
    }
}

private func inferredRichSpans(from text: String, goal: String) -> [SessionReviewInlineSpan] {
    let quotedSegments = splitQuotedSegments(in: text)
    var spans: [SessionReviewInlineSpan] = []
    var usedEntityRefs: Set<String> = []

    for segment in quotedSegments {
        if segment.isQuoted {
            let cleaned = cleanedTitleLabel(segment.text)
            if !cleaned.isEmpty {
                spans.append(SessionReviewInlineSpan(kind: .title, text: cleaned))
            }
            continue
        }

        spans.append(contentsOf: inferredPlainSpans(from: segment.text, goal: goal, usedEntityRefs: &usedEntityRefs))
    }

    return compactedRichSpans(spans)
}

private func inferredPlainSpans(
    from text: String,
    goal: String,
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
        ("Safari", "app", "safari"),
        ("Chrome", "app", "chrome"),
        ("GitHub", "site", "github"),
        ("Spotify", "app", "spotify"),
        ("Notion", "site", "notion"),
        ("Cursor", "app", "cursor"),
        ("Codex", "app", "codex"),
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
                        referenceID: pattern.ref
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
                    referenceID: span.referenceID
                )
            )
        }
    }

    return result
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

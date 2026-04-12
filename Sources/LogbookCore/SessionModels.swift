import Foundation

public struct FocusSession: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let durationMinutes: Int
    public let startedAt: Date
    public let endsAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        durationMinutes: Int,
        startedAt: Date = Date(),
        endsAt: Date
    ) {
        self.id = id
        self.title = title
        self.durationMinutes = durationMinutes
        self.startedAt = startedAt
        self.endsAt = endsAt
    }
}

public enum ActivityCategory: String, Codable, CaseIterable {
    case coding
    case docs
    case communication
    case admin
    case research
    case media
    case social
    case unknown

    public var title: String {
        rawValue.capitalized
    }
}

public enum DerivedEntityKind: String, Codable, CaseIterable {
    case repo
    case file
    case web
    case note
    case presence
    case system
    case app
    case unknown
}

public struct DerivedEntity: Identifiable, Hashable, Codable {
    public let id: String
    public let kind: DerivedEntityKind
    public let primaryLabel: String
    public let secondaryLabel: String?
    public let repoName: String?
    public let filePath: String?
    public let url: String?
    public let domain: String?
    public let confidence: Double

    public init(
        id: String = UUID().uuidString,
        kind: DerivedEntityKind,
        primaryLabel: String,
        secondaryLabel: String? = nil,
        repoName: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        domain: String? = nil,
        confidence: Double = 0.5
    ) {
        self.id = id
        self.kind = kind
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.repoName = repoName
        self.filePath = filePath
        self.url = url
        self.domain = domain
        self.confidence = confidence
    }
}

public struct TimelineSegment: Identifiable, Hashable, Codable {
    public let id: String
    public let startAt: Date
    public let endAt: Date
    public let appName: String
    public let primaryLabel: String
    public let secondaryLabel: String?
    public let category: ActivityCategory
    public let repoName: String?
    public let filePath: String?
    public let url: String?
    public let domain: String?
    public let confidence: Double
    public let eventCount: Int

    public init(
        id: String = UUID().uuidString,
        startAt: Date,
        endAt: Date,
        appName: String,
        primaryLabel: String,
        secondaryLabel: String? = nil,
        category: ActivityCategory = .unknown,
        repoName: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        domain: String? = nil,
        confidence: Double = 0.5,
        eventCount: Int = 0
    ) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.appName = appName
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.category = category
        self.repoName = repoName
        self.filePath = filePath
        self.url = url
        self.domain = domain
        self.confidence = confidence
        self.eventCount = eventCount
    }
}

public enum SessionSegmentRole: String, Codable, CaseIterable {
    case direct
    case support
    case drift
    case breakTime = "break"
    case neutral

    public var title: String {
        switch self {
        case .direct:
            return "Direct"
        case .support:
            return "Support"
        case .drift:
            return "Drift"
        case .breakTime:
            return "Break"
        case .neutral:
            return "Neutral"
        }
    }
}

public enum SessionIntentMode: String, Codable, CaseIterable {
    case build
    case review
    case write
    case research
    case browse
    case watch
    case listen
    case communicate
    case admin
    case mixed
    case unknown
}

public struct SessionIntent: Hashable, Codable {
    public let rawGoal: String
    public let mode: SessionIntentMode
    public let action: String?
    public let targets: [String]
    public let objects: [String]
    public let confidence: Double

    public init(
        rawGoal: String,
        mode: SessionIntentMode,
        action: String? = nil,
        targets: [String] = [],
        objects: [String] = [],
        confidence: Double = 0.0
    ) {
        self.rawGoal = rawGoal
        self.mode = mode
        self.action = action
        self.targets = targets
        self.objects = objects
        self.confidence = confidence
    }
}

public enum SessionGoalProgressEstimate: String, Codable, CaseIterable {
    case strong
    case partial
    case weak
    case none

    public var title: String {
        rawValue.capitalized
    }
}

public struct ObservedTimelineSegment: Identifiable, Hashable, Codable {
    public let id: String
    public let segment: TimelineSegment
    public let role: SessionSegmentRole
    public let goalRelevance: Double
    public let rationale: String

    public init(
        id: String = UUID().uuidString,
        segment: TimelineSegment,
        role: SessionSegmentRole,
        goalRelevance: Double,
        rationale: String
    ) {
        self.id = id
        self.segment = segment
        self.role = role
        self.goalRelevance = goalRelevance
        self.rationale = rationale
    }
}

public struct SessionObservabilitySummary: Hashable, Codable {
    public let directSeconds: Int
    public let supportSeconds: Int
    public let driftSeconds: Int
    public let breakSeconds: Int
    public let neutralSeconds: Int
    public let longestDirectRunSeconds: Int
    public let driftInterruptions: Int
    public let goalProgressEstimate: SessionGoalProgressEstimate

    public init(
        directSeconds: Int = 0,
        supportSeconds: Int = 0,
        driftSeconds: Int = 0,
        breakSeconds: Int = 0,
        neutralSeconds: Int = 0,
        longestDirectRunSeconds: Int = 0,
        driftInterruptions: Int = 0,
        goalProgressEstimate: SessionGoalProgressEstimate = .none
    ) {
        self.directSeconds = directSeconds
        self.supportSeconds = supportSeconds
        self.driftSeconds = driftSeconds
        self.breakSeconds = breakSeconds
        self.neutralSeconds = neutralSeconds
        self.longestDirectRunSeconds = longestDirectRunSeconds
        self.driftInterruptions = driftInterruptions
        self.goalProgressEstimate = goalProgressEstimate
    }
}

public enum ReviewStatus: String, Codable, CaseIterable {
    case none
    case pending
    case ready
    case unavailable
    case failed
}

public enum SessionQuality: String, Codable, CaseIterable {
    case coherent
    case mixed
    case drifted
    
    public var title: String {
        rawValue.capitalized
    }
}

public enum SessionGoalMatch: String, Codable, CaseIterable {
    case strong
    case partial
    case weak
    case unclear

    public var title: String {
        rawValue.capitalized
    }
}

public enum SessionVerdict: String, Codable, CaseIterable {
    case matched
    case partiallyMatched = "partially_matched"
    case missed

    public var title: String {
        switch self {
        case .matched:
            return "Matched"
        case .partiallyMatched:
            return "Partially matched"
        case .missed:
            return "Missed"
        }
    }

    public init(goalMatch: SessionGoalMatch) {
        switch goalMatch {
        case .strong:
            self = .matched
        case .partial, .unclear:
            self = .partiallyMatched
        case .weak:
            self = .missed
        }
    }
}

public struct SessionEvidenceSummary: Hashable, Codable {
    public let topApps: [String]
    public let topTitles: [String]
    public let topURLs: [String]
    public let topPaths: [String]
    public let commands: [String]
    public let clipboardPreviews: [String]
    public let quickNotes: [String]
    public let calendarTitles: [String]
    public let trace: [SessionTimelineEntry]

    public init(
        topApps: [String] = [],
        topTitles: [String] = [],
        topURLs: [String] = [],
        topPaths: [String] = [],
        commands: [String] = [],
        clipboardPreviews: [String] = [],
        quickNotes: [String] = [],
        calendarTitles: [String] = [],
        trace: [SessionTimelineEntry] = []
    ) {
        self.topApps = topApps
        self.topTitles = topTitles
        self.topURLs = topURLs
        self.topPaths = topPaths
        self.commands = commands
        self.clipboardPreviews = clipboardPreviews
        self.quickNotes = quickNotes
        self.calendarTitles = calendarTitles
        self.trace = trace
    }

    public static let empty = SessionEvidenceSummary()
}

public enum AttentionConfidence: String, Codable, CaseIterable {
    case high
    case medium
    case low
}

public enum AttentionOverlayKind: String, Codable, CaseIterable {
    case audio
    case note
    case system
    case context
}

public struct AttentionOverlay: Identifiable, Hashable, Codable {
    public let id: String
    public let kind: AttentionOverlayKind
    public let segment: TimelineSegment
    public let confidence: AttentionConfidence

    public init(
        id: String = UUID().uuidString,
        kind: AttentionOverlayKind,
        segment: TimelineSegment,
        confidence: AttentionConfidence
    ) {
        self.id = id
        self.kind = kind
        self.segment = segment
        self.confidence = confidence
    }
}

public struct AttentionSegment: Identifiable, Hashable, Codable {
    public let id: String
    public let foreground: TimelineSegment
    public let overlays: [AttentionOverlay]
    public let confidence: AttentionConfidence

    public init(
        id: String = UUID().uuidString,
        foreground: TimelineSegment,
        overlays: [AttentionOverlay] = [],
        confidence: AttentionConfidence
    ) {
        self.id = id
        self.foreground = foreground
        self.overlays = overlays
        self.confidence = confidence
    }
}

public struct SessionReview: Identifiable, Hashable, Codable {
    public let id: String
    public let sessionTitle: String
    public let startedAt: Date
    public let endedAt: Date
    public let verdict: SessionVerdict
    public let quality: SessionQuality
    public let goalMatch: SessionGoalMatch
    public let headline: String
    public let summary: String
    public let summarySpans: [SessionReviewInlineSpan]
    public let why: String
    public let interruptions: [String]
    public let interruptionSpans: [[SessionReviewInlineSpan]]
    public let reasons: [String]
    public let timeline: [SessionTimelineEntry]
    public let trace: [SessionTimelineEntry]
    public let evidence: SessionEvidenceSummary
    public let links: [SessionReferenceLink]
    public let appDurations: [SessionAppDuration]
    public let appSwitchCount: Int
    public let repoName: String?
    public let nearbyEventTitle: String?
    public let mediaSummary: String?
    public let clipboardPreview: String?
    public let dominantApps: [String]
    public let sessionPath: [String]
    public let breakPointAtLabel: String?
    public let breakPoint: String?
    public let dominantThread: String?
    public let referenceURL: String?
    public let focusAssessment: String?
    public let confidenceNotes: [String]
    public let segments: [TimelineSegment]
    public let attentionSegments: [AttentionSegment]
    
    public init(
        id: String = UUID().uuidString,
        sessionTitle: String,
        startedAt: Date,
        endedAt: Date,
        verdict: SessionVerdict? = nil,
        quality: SessionQuality,
        goalMatch: SessionGoalMatch = .unclear,
        headline: String,
        summary: String? = nil,
        summarySpans: [SessionReviewInlineSpan] = [],
        why: String,
        interruptions: [String] = [],
        interruptionSpans: [[SessionReviewInlineSpan]] = [],
        reasons: [String] = [],
        timeline: [SessionTimelineEntry] = [],
        trace: [SessionTimelineEntry] = [],
        evidence: SessionEvidenceSummary = .empty,
        links: [SessionReferenceLink] = [],
        appDurations: [SessionAppDuration] = [],
        appSwitchCount: Int = 0,
        repoName: String? = nil,
        nearbyEventTitle: String? = nil,
        mediaSummary: String? = nil,
        clipboardPreview: String? = nil,
        dominantApps: [String] = [],
        sessionPath: [String] = [],
        breakPointAtLabel: String? = nil,
        breakPoint: String? = nil,
        dominantThread: String? = nil,
        referenceURL: String? = nil,
        focusAssessment: String? = nil,
        confidenceNotes: [String] = [],
        segments: [TimelineSegment] = [],
        attentionSegments: [AttentionSegment] = []
    ) {
        self.id = id
        self.sessionTitle = sessionTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.verdict = verdict ?? SessionVerdict(goalMatch: goalMatch)
        self.quality = quality
        self.goalMatch = goalMatch
        self.headline = headline
        self.summary = summary ?? why
        self.summarySpans = summarySpans
        self.why = why
        self.interruptions = interruptions
        self.interruptionSpans = interruptionSpans
        self.reasons = reasons
        self.timeline = timeline
        self.trace = trace
        self.evidence = evidence
        self.links = links
        self.appDurations = appDurations
        self.appSwitchCount = appSwitchCount
        self.repoName = repoName
        self.nearbyEventTitle = nearbyEventTitle
        self.mediaSummary = mediaSummary
        self.clipboardPreview = clipboardPreview
        self.dominantApps = dominantApps
        self.sessionPath = sessionPath
        self.breakPointAtLabel = breakPointAtLabel
        self.breakPoint = breakPoint
        self.dominantThread = dominantThread
        self.referenceURL = referenceURL
        self.focusAssessment = focusAssessment
        self.confidenceNotes = confidenceNotes
        self.segments = segments
        self.attentionSegments = attentionSegments
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionTitle
        case startedAt
        case endedAt
        case verdict
        case quality
        case goalMatch
        case headline
        case summary
        case summarySpans
        case why
        case interruptions
        case interruptionSpans
        case reasons
        case timeline
        case trace
        case evidence
        case links
        case appDurations
        case appSwitchCount
        case repoName
        case nearbyEventTitle
        case mediaSummary
        case clipboardPreview
        case dominantApps
        case sessionPath
        case breakPointAtLabel
        case breakPoint
        case dominantThread
        case referenceURL
        case focusAssessment
        case confidenceNotes
        case segments
        case attentionSegments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionTitle = try container.decode(String.self, forKey: .sessionTitle)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        quality = try container.decode(SessionQuality.self, forKey: .quality)
        goalMatch = try container.decodeIfPresent(SessionGoalMatch.self, forKey: .goalMatch) ?? .unclear
        verdict = try container.decodeIfPresent(SessionVerdict.self, forKey: .verdict) ?? SessionVerdict(goalMatch: goalMatch)
        headline = try container.decode(String.self, forKey: .headline)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? (try container.decode(String.self, forKey: .why))
        summarySpans = try container.decodeIfPresent([SessionReviewInlineSpan].self, forKey: .summarySpans) ?? []
        why = try container.decode(String.self, forKey: .why)
        interruptions = try container.decodeIfPresent([String].self, forKey: .interruptions) ?? []
        interruptionSpans = try container.decodeIfPresent([[SessionReviewInlineSpan]].self, forKey: .interruptionSpans) ?? []
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        timeline = try container.decodeIfPresent([SessionTimelineEntry].self, forKey: .timeline) ?? []
        trace = try container.decodeIfPresent([SessionTimelineEntry].self, forKey: .trace) ?? []
        evidence = try container.decodeIfPresent(SessionEvidenceSummary.self, forKey: .evidence)
            ?? SessionEvidenceSummary(
                topApps: try container.decodeIfPresent([String].self, forKey: .dominantApps) ?? [],
                topURLs: (try container.decodeIfPresent([SessionReferenceLink].self, forKey: .links) ?? []).map(\.url),
                topPaths: try container.decodeIfPresent([String].self, forKey: .sessionPath) ?? [],
                clipboardPreviews: [try container.decodeIfPresent(String.self, forKey: .clipboardPreview)].compactMap { $0 },
                calendarTitles: [try container.decodeIfPresent(String.self, forKey: .nearbyEventTitle)].compactMap { $0 },
                trace: try container.decodeIfPresent([SessionTimelineEntry].self, forKey: .trace) ?? []
            )
        links = try container.decodeIfPresent([SessionReferenceLink].self, forKey: .links) ?? []
        appDurations = try container.decodeIfPresent([SessionAppDuration].self, forKey: .appDurations) ?? []
        appSwitchCount = try container.decodeIfPresent(Int.self, forKey: .appSwitchCount) ?? 0
        repoName = try container.decodeIfPresent(String.self, forKey: .repoName)
        nearbyEventTitle = try container.decodeIfPresent(String.self, forKey: .nearbyEventTitle)
        mediaSummary = try container.decodeIfPresent(String.self, forKey: .mediaSummary)
        clipboardPreview = try container.decodeIfPresent(String.self, forKey: .clipboardPreview)
        dominantApps = try container.decodeIfPresent([String].self, forKey: .dominantApps) ?? []
        sessionPath = try container.decodeIfPresent([String].self, forKey: .sessionPath) ?? []
        breakPointAtLabel = try container.decodeIfPresent(String.self, forKey: .breakPointAtLabel)
        breakPoint = try container.decodeIfPresent(String.self, forKey: .breakPoint)
        dominantThread = try container.decodeIfPresent(String.self, forKey: .dominantThread)
        referenceURL = try container.decodeIfPresent(String.self, forKey: .referenceURL)
        focusAssessment = try container.decodeIfPresent(String.self, forKey: .focusAssessment)
        confidenceNotes = try container.decodeIfPresent([String].self, forKey: .confidenceNotes) ?? []
        segments = try container.decodeIfPresent([TimelineSegment].self, forKey: .segments) ?? []
        attentionSegments = try container.decodeIfPresent([AttentionSegment].self, forKey: .attentionSegments) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionTitle, forKey: .sessionTitle)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(verdict, forKey: .verdict)
        try container.encode(quality, forKey: .quality)
        try container.encode(goalMatch, forKey: .goalMatch)
        try container.encode(headline, forKey: .headline)
        try container.encode(summary, forKey: .summary)
        try container.encode(summarySpans, forKey: .summarySpans)
        try container.encode(why, forKey: .why)
        try container.encode(interruptions, forKey: .interruptions)
        try container.encode(interruptionSpans, forKey: .interruptionSpans)
        try container.encode(reasons, forKey: .reasons)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(trace, forKey: .trace)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(links, forKey: .links)
        try container.encode(appDurations, forKey: .appDurations)
        try container.encode(appSwitchCount, forKey: .appSwitchCount)
        try container.encodeIfPresent(repoName, forKey: .repoName)
        try container.encodeIfPresent(nearbyEventTitle, forKey: .nearbyEventTitle)
        try container.encodeIfPresent(mediaSummary, forKey: .mediaSummary)
        try container.encodeIfPresent(clipboardPreview, forKey: .clipboardPreview)
        try container.encode(dominantApps, forKey: .dominantApps)
        try container.encode(sessionPath, forKey: .sessionPath)
        try container.encodeIfPresent(breakPointAtLabel, forKey: .breakPointAtLabel)
        try container.encodeIfPresent(breakPoint, forKey: .breakPoint)
        try container.encodeIfPresent(dominantThread, forKey: .dominantThread)
        try container.encodeIfPresent(referenceURL, forKey: .referenceURL)
        try container.encodeIfPresent(focusAssessment, forKey: .focusAssessment)
        try container.encode(confidenceNotes, forKey: .confidenceNotes)
        try container.encode(segments, forKey: .segments)
        try container.encode(attentionSegments, forKey: .attentionSegments)
    }
}

public struct SessionReviewInlineSpan: Hashable, Codable {
    public enum Kind: String, Hashable, Codable {
        case text
        case entity
        case title
        case goal
        case code
        case file
    }

    public let kind: Kind
    public let text: String
    public let entityKind: String?
    public let referenceID: String?
    public let url: String?

    public init(
        kind: Kind,
        text: String,
        entityKind: String? = nil,
        referenceID: String? = nil,
        url: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.entityKind = entityKind
        self.referenceID = referenceID
        self.url = url
    }
}

public struct StoredSession: Identifiable, Hashable, Codable {
    public let id: String
    public let goal: String
    public let startedAt: Date
    public let endedAt: Date
    public let verdict: SessionVerdict?
    public let headline: String?
    public let summary: String?
    public let reviewStatus: ReviewStatus
    public let primaryLabels: [String]

    public init(
        id: String,
        goal: String,
        startedAt: Date,
        endedAt: Date,
        verdict: SessionVerdict? = nil,
        headline: String? = nil,
        summary: String? = nil,
        reviewStatus: ReviewStatus = .none,
        primaryLabels: [String] = []
    ) {
        self.id = id
        self.goal = goal
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.verdict = verdict
        self.headline = headline
        self.summary = summary
        self.reviewStatus = reviewStatus
        self.primaryLabels = primaryLabels
    }
}

public struct StoredSessionReview: Hashable, Codable {
    public let sessionID: String
    public let generatedAt: Date
    public let providerTitle: String
    public let review: SessionReview
    public let debugPrompt: String?
    public let debugRawResponse: String?

    public init(
        sessionID: String,
        generatedAt: Date = Date(),
        providerTitle: String,
        review: SessionReview,
        debugPrompt: String? = nil,
        debugRawResponse: String? = nil
    ) {
        self.sessionID = sessionID
        self.generatedAt = generatedAt
        self.providerTitle = providerTitle
        self.review = review
        self.debugPrompt = debugPrompt
        self.debugRawResponse = debugRawResponse
    }
}

public struct SessionReviewFeedback: Hashable, Codable {
    public let sessionID: String
    public let createdAt: Date
    public let wasHelpful: Bool
    public let note: String?
    public let goalSnapshot: String
    public let reviewHeadlineSnapshot: String
    public let reviewSummarySnapshot: String
    public let reviewTakeawaySnapshot: String?

    public init(
        sessionID: String,
        createdAt: Date = Date(),
        wasHelpful: Bool,
        note: String? = nil,
        goalSnapshot: String,
        reviewHeadlineSnapshot: String,
        reviewSummarySnapshot: String,
        reviewTakeawaySnapshot: String? = nil
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.wasHelpful = wasHelpful
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        self.goalSnapshot = goalSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reviewHeadlineSnapshot = reviewHeadlineSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reviewSummarySnapshot = reviewSummarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reviewTakeawaySnapshot = reviewTakeawaySnapshot?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SessionReviewFeedbackExample: Hashable, Codable, Identifiable {
    public enum Label: String, Hashable, Codable {
        case confirmed
        case correction
    }

    public let id: String
    public let sessionID: String
    public let createdAt: Date
    public let goal: String
    public let reviewSaid: String
    public let userFeedback: String
    public let label: Label

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        createdAt: Date,
        goal: String,
        reviewSaid: String,
        userFeedback: String,
        label: Label
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.goal = goal
        self.reviewSaid = reviewSaid
        self.userFeedback = userFeedback
        self.label = label
    }
}

public struct SessionReviewLearningMemory: Hashable, Codable {
    public let updatedAt: Date
    public let sourceFeedbackCount: Int
    public let learnings: [String]

    public init(
        updatedAt: Date = Date(),
        sourceFeedbackCount: Int,
        learnings: [String]
    ) {
        self.updatedAt = updatedAt
        self.sourceFeedbackCount = sourceFeedbackCount
        self.learnings = learnings
    }
}

public struct StoredSessionDetail: Hashable {
    public let session: StoredSession
    public let review: StoredSessionReview?
    public let segments: [TimelineSegment]
    public let rawEventCount: Int

    public init(
        session: StoredSession,
        review: StoredSessionReview?,
        segments: [TimelineSegment],
        rawEventCount: Int
    ) {
        self.session = session
        self.review = review
        self.segments = segments
        self.rawEventCount = rawEventCount
    }
}

public struct SessionAppDuration: Identifiable, Hashable, Codable {
    public let id: String
    public let appName: String
    public let minutesLabel: String

    public init(id: String = UUID().uuidString, appName: String, minutesLabel: String) {
        self.id = id
        self.appName = appName
        self.minutesLabel = minutesLabel
    }
}

public struct SessionTimelineEntry: Identifiable, Hashable, Codable {
    public let id: String
    public let at: String
    public let text: String
    public let url: String?
    
    public init(id: String = UUID().uuidString, at: String, text: String, url: String? = nil) {
        self.id = id
        self.at = at
        self.text = text
        self.url = url
    }
}

public struct SessionReferenceLink: Identifiable, Hashable, Codable {
    public let id: String
    public let title: String
    public let url: String
    
    public init(id: String = UUID().uuidString, title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }
}

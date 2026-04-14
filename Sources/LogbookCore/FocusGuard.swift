import Foundation

public enum FocusGuardStatus: String, Hashable, Codable, CaseIterable {
    case onTrack
    case unclear
    case offTrack

    public var title: String {
        switch self {
        case .onTrack:
            return "On track"
        case .unclear:
            return "Mixed"
        case .offTrack:
            return "Drift risk"
        }
    }
}

public enum FocusGuardPromptDelivery: String, Hashable, Codable, CaseIterable {
    case inApp
    case notification
}

public enum FocusGuardPreset: String, Hashable, Codable, CaseIterable {
    case off
    case balanced
    case strict

    public var title: String {
        switch self {
        case .off:
            return "Off"
        case .balanced:
            return "Balanced"
        case .strict:
            return "Strict"
        }
    }

    public var subtitle: String {
        switch self {
        case .off:
            return "No focus notifications. Drift still shows up in the review."
        case .balanced:
            return "Quiet default with light nudges."
        case .strict:
            return "Earlier nudges for tighter guardrails."
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "LogBook keeps tracking drift and recovery in the session review, but it never sends a focus notification."
        case .balanced:
            return "Checks every 30 seconds, can nudge after about a minute of clear drift, and scales from one nudge in short sessions to up to three in longer ones."
        case .strict:
            return "Checks every 30 seconds, nudges sooner when drift looks clear, and still keeps the notifications capped so it does not become noisy."
        }
    }

    public var settings: FocusGuardSettings {
        switch self {
        case .off:
            return FocusGuardSettings(enabled: false)
        case .balanced:
            return FocusGuardSettings(
                enabled: true,
                startAfterMinutes: 2,
                driftThresholdSeconds: 60,
                cooldownMinutes: 5,
                maxPromptsPerSession: 3
            )
        case .strict:
            return FocusGuardSettings(
                enabled: true,
                startAfterMinutes: 1,
                driftThresholdSeconds: 45,
                cooldownMinutes: 3,
                maxPromptsPerSession: 3
            )
        }
    }
}

public struct FocusGuardSettings: Hashable, Codable {
    public var enabled: Bool
    public var startAfterMinutes: Int
    public var driftThresholdSeconds: Int
    public var cooldownMinutes: Int
    public var maxPromptsPerSession: Int

    public init(
        enabled: Bool = true,
        startAfterMinutes: Int = 5,
        driftThresholdSeconds: Int = 90,
        cooldownMinutes: Int = 10,
        maxPromptsPerSession: Int = 2
    ) {
        self.enabled = enabled
        self.startAfterMinutes = startAfterMinutes
        self.driftThresholdSeconds = driftThresholdSeconds
        self.cooldownMinutes = cooldownMinutes
        self.maxPromptsPerSession = maxPromptsPerSession
    }
}

public struct FocusGuardAssessment: Hashable {
    public let status: FocusGuardStatus
    public let modeSnapshot: ModeSnapshot
    public let reason: String
    public let matchedLabels: [String]
    public let driftLabels: [String]
    public let lastEvaluatedAt: Date?

    public init(
        status: FocusGuardStatus,
        modeSnapshot: ModeSnapshot,
        reason: String,
        matchedLabels: [String] = [],
        driftLabels: [String] = [],
        lastEvaluatedAt: Date? = nil
    ) {
        self.status = status
        self.modeSnapshot = modeSnapshot
        self.reason = reason
        self.matchedLabels = matchedLabels
        self.driftLabels = driftLabels
        self.lastEvaluatedAt = lastEvaluatedAt
    }

    public static let empty = FocusGuardAssessment(
        status: .unclear,
        modeSnapshot: .empty,
        reason: "Waiting for a little more session activity.",
        lastEvaluatedAt: nil
    )
}

public struct FocusGuardPrompt: Identifiable, Hashable, Codable {
    public let id: String
    public let sessionID: String
    public let message: String
    public let reason: String
    public let shownAt: Date
    public let delivery: FocusGuardPromptDelivery

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        message: String,
        reason: String,
        shownAt: Date,
        delivery: FocusGuardPromptDelivery
    ) {
        self.id = id
        self.sessionID = sessionID
        self.message = message
        self.reason = reason
        self.shownAt = shownAt
        self.delivery = delivery
    }
}

public struct FocusGuardRuntimeState: Hashable, Codable {
    public var offTrackStartedAt: Date?
    public var snoozedUntil: Date?
    public var lastPromptAt: Date?
    public var promptCount: Int
    public var pendingRecoveryFromPromptAt: Date?
    public var lastRecoveryAt: Date?

    public init(
        offTrackStartedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        lastPromptAt: Date? = nil,
        promptCount: Int = 0,
        pendingRecoveryFromPromptAt: Date? = nil,
        lastRecoveryAt: Date? = nil
    ) {
        self.offTrackStartedAt = offTrackStartedAt
        self.snoozedUntil = snoozedUntil
        self.lastPromptAt = lastPromptAt
        self.promptCount = promptCount
        self.pendingRecoveryFromPromptAt = pendingRecoveryFromPromptAt
        self.lastRecoveryAt = lastRecoveryAt
    }
}

public struct FocusGuardDecision: Hashable {
    public let assessment: FocusGuardAssessment
    public let state: FocusGuardRuntimeState
    public let shouldPrompt: Bool
    public let promptMessage: String?
    public let promptReason: String?
    public let recordedRecovery: Bool

    public init(
        assessment: FocusGuardAssessment,
        state: FocusGuardRuntimeState,
        shouldPrompt: Bool = false,
        promptMessage: String? = nil,
        promptReason: String? = nil,
        recordedRecovery: Bool = false
    ) {
        self.assessment = assessment
        self.state = state
        self.shouldPrompt = shouldPrompt
        self.promptMessage = promptMessage
        self.promptReason = promptReason
        self.recordedRecovery = recordedRecovery
    }
}

public struct FocusGuardReviewSummary: Hashable, Codable {
    public let promptsShown: Int
    public let snoozes: Int
    public let ignores: Int
    public let recoveries: Int
    public let lastRecoveryAt: Date?
    public let unresolvedDrift: Bool
    public let recapSentence: String?

    public init(
        promptsShown: Int,
        snoozes: Int,
        ignores: Int,
        recoveries: Int,
        lastRecoveryAt: Date?,
        unresolvedDrift: Bool,
        recapSentence: String?
    ) {
        self.promptsShown = promptsShown
        self.snoozes = snoozes
        self.ignores = ignores
        self.recoveries = recoveries
        self.lastRecoveryAt = lastRecoveryAt
        self.unresolvedDrift = unresolvedDrift
        self.recapSentence = recapSentence
    }

    public static let empty = FocusGuardReviewSummary(
        promptsShown: 0,
        snoozes: 0,
        ignores: 0,
        recoveries: 0,
        lastRecoveryAt: nil,
        unresolvedDrift: false,
        recapSentence: nil
    )
}

public enum FocusGuardEvaluator {
    public static func evaluate(
        goal: String,
        session: FocusSession,
        events: [ActivityEvent],
        settings: FocusGuardSettings = FocusGuardSettings(),
        state: FocusGuardRuntimeState = FocusGuardRuntimeState(),
        now: Date = Date(),
        isUserIdle: Bool
    ) -> FocusGuardDecision {
        let relevantEvents = events
            .filter { $0.occurredAt >= session.startedAt && $0.occurredAt <= now }
            .filter { !$0.kind.isFocusGuardSignal }
            .sorted { $0.occurredAt < $1.occurredAt }

        let modeSnapshot = ModeEngine.snapshot(events: relevantEvents, now: now)
        let sessionPaused = isUserIdle || isSessionPaused(relevantEvents)
        let recentWindowStart = max(session.startedAt, now.addingTimeInterval(-3 * 60))
        let recentEvents = relevantEvents.filter { $0.occurredAt >= recentWindowStart }
        let recentSegments = TimelineDeriver.deriveSegments(from: recentEvents, sessionEnd: now)
        let observed = TimelineDeriver.observeSegments(recentSegments, goal: goal)
        let observability = TimelineDeriver.summarizeObservedSegments(observed)
        let matchedLabels = uniqueObservedLabels(from: observed, roles: [.direct, .support], limit: 3)
        let driftLabels = uniqueObservedLabels(from: observed, roles: [.drift, .breakTime], limit: 3)
        let productiveSeconds = observability.directSeconds + observability.supportSeconds
        let driftSeconds = observability.driftSeconds + observability.breakSeconds
        let totalSeconds = max(productiveSeconds + driftSeconds + observability.neutralSeconds, 1)
        let productiveRatio = Double(productiveSeconds) / Double(totalSeconds)
        let driftLeadLabel = driftLabels.first ?? fallbackDriftLabel(from: modeSnapshot)
        let offTrackWindowStart = observed
            .first(where: { $0.role == .drift || $0.role == .breakTime })?
            .segment
            .startAt

        let assessmentStatus: FocusGuardStatus
        let reason: String

        if recentSegments.isEmpty {
            assessmentStatus = .unclear
            reason = "Waiting for a little more activity."
        } else if modeSnapshot.mode == .drifting || modeSnapshot.mode == .decompressing,
                  driftLeadLabel != nil,
                  driftSeconds >= 45,
                  driftSeconds >= productiveSeconds + 30,
                  productiveRatio <= 0.45 {
            assessmentStatus = .offTrack
            reason = "Recent activity looks more like \(driftLeadLabel ?? "drift") than work on this goal."
        } else if !matchedLabels.isEmpty,
                  (productiveRatio >= 0.55 || productiveSeconds >= 120) {
            assessmentStatus = .onTrack
            reason = "Recent activity still lines up with \(matchedLabels.first ?? "the session goal")."
        } else {
            assessmentStatus = .unclear
            reason = "Recent activity is mixed."
        }

        let assessment = FocusGuardAssessment(
            status: assessmentStatus,
            modeSnapshot: modeSnapshot,
            reason: reason,
            matchedLabels: matchedLabels,
            driftLabels: driftLabels,
            lastEvaluatedAt: now
        )

        var updatedState = state
        var recordedRecovery = false

        if let pendingRecoveryFromPromptAt = updatedState.pendingRecoveryFromPromptAt {
            if now.timeIntervalSince(pendingRecoveryFromPromptAt) > 2 * 60 {
                updatedState.pendingRecoveryFromPromptAt = nil
            } else if assessment.status == .onTrack {
                updatedState.pendingRecoveryFromPromptAt = nil
                updatedState.lastRecoveryAt = now
                recordedRecovery = true
            }
        }

        if assessment.status == .offTrack {
            if updatedState.offTrackStartedAt == nil {
                updatedState.offTrackStartedAt = offTrackWindowStart ?? recentSegments.first?.startAt ?? now
            }
        } else {
            updatedState.offTrackStartedAt = nil
        }

        guard settings.enabled else {
            return FocusGuardDecision(assessment: assessment, state: updatedState, recordedRecovery: recordedRecovery)
        }

        let startedLongEnough = now.timeIntervalSince(session.startedAt) >= TimeInterval(startDelayMinutes(for: session, settings: settings) * 60)
        let remainingSeconds = session.endsAt.timeIntervalSince(now)
        let minimumRemainingSeconds = endBufferSeconds(for: session)
        let inCooldown = updatedState.lastPromptAt.map {
            now.timeIntervalSince($0) < TimeInterval(settings.cooldownMinutes * 60)
        } ?? false
        let snoozed = updatedState.snoozedUntil.map { $0 > now } ?? false
        let canPrompt = startedLongEnough
            && !sessionPaused
            && remainingSeconds > minimumRemainingSeconds
            && !inCooldown
            && !snoozed
            && updatedState.promptCount < promptCap(for: session, settings: settings)
            && assessment.status == .offTrack

        guard canPrompt,
              let offTrackStartedAt = updatedState.offTrackStartedAt,
              now.timeIntervalSince(offTrackStartedAt) >= TimeInterval(settings.driftThresholdSeconds) else {
            return FocusGuardDecision(assessment: assessment, state: updatedState, recordedRecovery: recordedRecovery)
        }

        updatedState.lastPromptAt = now
        updatedState.promptCount += 1
        updatedState.pendingRecoveryFromPromptAt = now
        updatedState.offTrackStartedAt = nil

        let promptMessage = promptMessage(for: driftLeadLabel, goal: goal)
        return FocusGuardDecision(
            assessment: assessment,
            state: updatedState,
            shouldPrompt: true,
            promptMessage: promptMessage,
            promptReason: reason,
            recordedRecovery: recordedRecovery
        )
    }

    public static func reviewSummary(from events: [ActivityEvent], sessionID: String? = nil) -> FocusGuardReviewSummary {
        let relevant = events
            .filter { $0.kind.isFocusGuardSignal }
            .filter { sessionID == nil || $0.relatedID == sessionID }
            .sorted { $0.occurredAt < $1.occurredAt }

        guard !relevant.isEmpty else { return .empty }

        let promptsShown = relevant.filter { $0.kind == .focusGuardPrompted }.count
        let snoozes = relevant.filter { $0.kind == .focusGuardSnoozed }.count
        let ignores = relevant.filter { $0.kind == .focusGuardIgnored }.count
        let recoveries = relevant.filter { $0.kind == .focusGuardRecovered }.count
        let lastRecoveryAt = relevant.last(where: { $0.kind == .focusGuardRecovered })?.occurredAt
        let unresolvedDrift = promptsShown > recoveries

        let recapSentence: String?
        if promptsShown == 0 {
            recapSentence = nil
        } else if recoveries > 0 {
            recapSentence = "You drifted during the block, but got back on track after \(recoveries == 1 ? "one prompt" : "\(recoveries) prompts")."
        } else if unresolvedDrift {
            recapSentence = "You drifted during the block and stayed off-track after \(promptsShown == 1 ? "one prompt" : "\(promptsShown) prompts")."
        } else {
            recapSentence = "A drift nudge showed up during the block."
        }

        return FocusGuardReviewSummary(
            promptsShown: promptsShown,
            snoozes: snoozes,
            ignores: ignores,
            recoveries: recoveries,
            lastRecoveryAt: lastRecoveryAt,
            unresolvedDrift: unresolvedDrift,
            recapSentence: recapSentence
        )
    }
}

private extension FocusGuardEvaluator {
    static func promptCap(for session: FocusSession, settings: FocusGuardSettings) -> Int {
        guard settings.maxPromptsPerSession > 0 else { return 0 }
        if session.durationMinutes < 15 {
            return min(settings.maxPromptsPerSession, 1)
        }
        if session.durationMinutes <= 30 {
            return min(settings.maxPromptsPerSession, 2)
        }
        return settings.maxPromptsPerSession
    }

    static func startDelayMinutes(for session: FocusSession, settings: FocusGuardSettings) -> Int {
        if session.durationMinutes < 10 {
            return min(settings.startAfterMinutes, 1)
        }
        return settings.startAfterMinutes
    }

    static func endBufferSeconds(for session: FocusSession) -> TimeInterval {
        session.durationMinutes < 10 ? 60 : 120
    }

    static func uniqueObservedLabels(
        from observed: [ObservedTimelineSegment],
        roles: Set<SessionSegmentRole>,
        limit: Int
    ) -> [String] {
        var labels: [String] = []
        var seen: Set<String> = []

        for item in observed where roles.contains(item.role) {
            let candidates = [item.segment.secondaryLabel, item.segment.primaryLabel, item.segment.appName].compactMap { $0 }
            guard let label = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                continue
            }
            if seen.insert(label).inserted {
                labels.append(label)
            }
            if labels.count >= limit {
                break
            }
        }

        return labels
    }

    static func fallbackDriftLabel(from snapshot: ModeSnapshot) -> String? {
        switch snapshot.mode {
        case .decompressing:
            return "passive media"
        case .drifting:
            return snapshot.apps.first?.lowercased() == "spotify" ? "passive media" : snapshot.apps.first
        default:
            return nil
        }
    }

    static func promptMessage(for driftLabel: String?, goal: String) -> String {
        let goalFragment = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let workTarget = goalFragment.isEmpty ? "your session" : goalFragment
        if let driftLabel, !driftLabel.isEmpty {
            return "You drifted to \(driftLabel). Back to \(workTarget)?"
        }
        return "You drifted off track. Back to \(workTarget)?"
    }

    static func isSessionPaused(_ events: [ActivityEvent]) -> Bool {
        guard let lastPauseEvent = events.last(where: {
            $0.kind == .userIdle || $0.kind == .userResumed || $0.kind == .systemSlept || $0.kind == .systemWoke
        }) else {
            return false
        }

        return lastPauseEvent.kind == .userIdle || lastPauseEvent.kind == .systemSlept
    }
}

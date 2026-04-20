import Foundation
import SQLite3

public final class SessionStore {
    private var db: OpaquePointer?
    private let path: URL
    public private(set) var startupError: SessionStoreError?

    public init(path: URL = DriftlyPaths.databaseURL) {
        self.path = path
        openDatabase()
        createSchema()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public var databasePath: String {
        path.path
    }

    public var isReady: Bool {
        db != nil
    }

    public func loadCaptureSettings() -> CaptureSettings {
        guard
            let db,
            let row = queryRow(db, sql: "SELECT json FROM settings WHERE id = 1"),
            let json = row.string("json"),
            let data = json.data(using: .utf8)
        else {
            return .default
        }

        do {
            return try settingsDecoder.decode(CaptureSettings.self, from: data)
        } catch {
            reportStoreIssue("Ignoring malformed settings row: \(error.localizedDescription)")
            return .default
        }
    }

    public func saveCaptureSettings(_ settings: CaptureSettings) throws {
        guard let db else { throw SessionStoreError.unavailable }
        let json = try jsonString(for: settings)
        try execute(
            db,
            sql: """
            INSERT INTO settings (id, json)
            VALUES (1, ?)
            ON CONFLICT(id) DO UPDATE SET json = excluded.json
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, json, -1, SQLITE_TRANSIENT)
            }
        )
    }

    @discardableResult
    public func insertEvent(_ event: ActivityEvent) throws -> Bool {
        guard let db else { throw SessionStoreError.unavailable }
        let payload = try jsonString(for: event)
        let inserted = try executeReturningBool(
            db,
            sql: """
            INSERT OR IGNORE INTO raw_events (
                id, occurred_at, source, kind, app_name, bundle_id, domain, working_directory, payload_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, event.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 2, event.occurredAt.timeIntervalSince1970)
                sqlite3_bind_text(statement, 3, event.source.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, event.kind.rawValue, -1, SQLITE_TRANSIENT)
                bindNullableText(event.appName, to: statement, index: 5)
                bindNullableText(event.bundleID, to: statement, index: 6)
                bindNullableText(event.domain, to: statement, index: 7)
                bindNullableText(event.workingDirectory, to: statement, index: 8)
                sqlite3_bind_text(statement, 9, payload, -1, SQLITE_TRANSIENT)
            }
        )
        return inserted
    }

    public func recentEvents(limit: Int = 5_000) -> [ActivityEvent] {
        fetchEvents(
            sql: """
            SELECT payload_json FROM raw_events
            ORDER BY occurred_at DESC
            LIMIT ?
            """,
            bind: { statement in
                sqlite3_bind_int(statement, 1, Int32(limit))
            }
        ).reversed()
    }

    public func events(between startAt: Date, and endAt: Date) -> [ActivityEvent] {
        fetchEvents(
            sql: """
            SELECT payload_json FROM raw_events
            WHERE occurred_at >= ? AND occurred_at <= ?
            ORDER BY occurred_at ASC
            """,
            bind: { statement in
                sqlite3_bind_double(statement, 1, startAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, endAt.timeIntervalSince1970)
            }
        )
    }

    public func clearAllEvents() throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(db, sql: "DELETE FROM raw_events")
    }

    public func pruneRawEvents(olderThan retentionDays: Int) throws {
        guard let db else { throw SessionStoreError.unavailable }
        let cutoff = Date().addingTimeInterval(TimeInterval(-max(retentionDays, 1) * 24 * 60 * 60))
        try execute(
            db,
            sql: "DELETE FROM raw_events WHERE occurred_at < ?",
            bind: { statement in
                sqlite3_bind_double(statement, 1, cutoff.timeIntervalSince1970)
            }
        )
    }

    public func clearModelDebugData() throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(db, sql: "UPDATE session_reviews SET debug_prompt = NULL, debug_raw_response = NULL")
    }

    public func clearSessionReview(sessionID: String) throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(
            db,
            sql: "DELETE FROM session_reviews WHERE session_id = ?",
            bind: { statement in
                sqlite3_bind_text(statement, 1, sessionID, -1, SQLITE_TRANSIENT)
            }
        )
    }

    public func saveReviewFeedback(_ feedback: SessionReviewFeedback) throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(
            db,
            sql: """
            INSERT INTO session_review_feedback (
                session_id, created_at, was_helpful, note, goal_snapshot, review_headline_snapshot, review_summary_snapshot, review_takeaway_snapshot
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                created_at = excluded.created_at,
                was_helpful = excluded.was_helpful,
                note = excluded.note,
                goal_snapshot = excluded.goal_snapshot,
                review_headline_snapshot = excluded.review_headline_snapshot,
                review_summary_snapshot = excluded.review_summary_snapshot,
                review_takeaway_snapshot = excluded.review_takeaway_snapshot
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, feedback.sessionID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 2, feedback.createdAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 3, feedback.wasHelpful ? 1 : 0)
                bindNullableText(feedback.note, to: statement, index: 4)
                sqlite3_bind_text(statement, 5, feedback.goalSnapshot, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 6, feedback.reviewHeadlineSnapshot, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 7, feedback.reviewSummarySnapshot, -1, SQLITE_TRANSIENT)
                bindNullableText(feedback.reviewTakeawaySnapshot, to: statement, index: 8)
            }
        )
    }

    public func reviewFeedback(sessionID: String) -> SessionReviewFeedback? {
        guard
            let db,
            let row = queryRow(db, sql: """
                SELECT session_id, created_at, was_helpful, note, goal_snapshot, review_headline_snapshot, review_summary_snapshot, review_takeaway_snapshot
                FROM session_review_feedback
                WHERE session_id = ?
                LIMIT 1
                """, bind: {
                    sqlite3_bind_text($0, 1, sessionID, -1, SQLITE_TRANSIENT)
                }),
            let storedSessionID = row.string("session_id"),
            let createdAtValue = row.double("created_at"),
            let wasHelpfulValue = row.int("was_helpful")
        else {
            return nil
        }

        return SessionReviewFeedback(
            sessionID: storedSessionID,
            createdAt: Date(timeIntervalSince1970: createdAtValue),
            wasHelpful: wasHelpfulValue != 0,
            note: row.string("note"),
            goalSnapshot: row.string("goal_snapshot") ?? "",
            reviewHeadlineSnapshot: row.string("review_headline_snapshot") ?? "",
            reviewSummarySnapshot: row.string("review_summary_snapshot") ?? "",
            reviewTakeawaySnapshot: row.string("review_takeaway_snapshot")
        )
    }

    public func recentReviewFeedback(limit: Int = 12, excludingSessionID: String? = nil) -> [SessionReviewFeedback] {
        guard let db else { return [] }
        let sql: String
        if excludingSessionID == nil {
            sql = """
            SELECT session_id, created_at, was_helpful, note, goal_snapshot, review_headline_snapshot, review_summary_snapshot, review_takeaway_snapshot
            FROM session_review_feedback
            ORDER BY created_at DESC
            LIMIT ?
            """
        } else {
            sql = """
            SELECT session_id, created_at, was_helpful, note, goal_snapshot, review_headline_snapshot, review_summary_snapshot, review_takeaway_snapshot
            FROM session_review_feedback
            WHERE session_id != ?
            ORDER BY created_at DESC
            LIMIT ?
            """
        }

        guard let statement = prepare(db, sql: sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        if let excludingSessionID {
            sqlite3_bind_text(statement, 1, excludingSessionID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 2, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 1, Int32(limit))
        }

        var rows: [SessionReviewFeedback] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let sessionID = string(from: statement, index: 0),
                let goalSnapshot = string(from: statement, index: 4),
                let reviewHeadlineSnapshot = string(from: statement, index: 5),
                let reviewSummarySnapshot = string(from: statement, index: 6)
            else {
                reportStoreIssue("Skipping malformed review feedback row.")
                continue
            }
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let wasHelpful = sqlite3_column_int(statement, 2) != 0
            let note = string(from: statement, index: 3)
            rows.append(
                SessionReviewFeedback(
                    sessionID: sessionID,
                    createdAt: createdAt,
                    wasHelpful: wasHelpful,
                    note: note,
                    goalSnapshot: goalSnapshot,
                    reviewHeadlineSnapshot: reviewHeadlineSnapshot,
                    reviewSummarySnapshot: reviewSummarySnapshot,
                    reviewTakeawaySnapshot: string(from: statement, index: 7)
                )
            )
        }

        return rows
    }

    public func promptReadyReviewFeedbackExamples(limit: Int = 4, maxPerPolarity: Int = 2) -> [SessionReviewFeedbackExample] {
        let feedback = recentReviewFeedback(limit: 100)
        var seenNotes: Set<String> = []
        var positiveCount = 0
        var negativeCount = 0
        var examples: [SessionReviewFeedbackExample] = []

        for item in feedback {
            guard let note = sanitizedFeedbackNote(item.note) else { continue }
            let noteKey = note.lowercased()
            guard seenNotes.insert(noteKey).inserted else { continue }

            if item.wasHelpful {
                guard positiveCount < maxPerPolarity else { continue }
                positiveCount += 1
            } else {
                guard negativeCount < maxPerPolarity else { continue }
                negativeCount += 1
            }

            examples.append(
                SessionReviewFeedbackExample(
                    sessionID: item.sessionID,
                    createdAt: item.createdAt,
                    goal: item.goalSnapshot,
                    reviewSaid: combinedReviewedResponse(from: item),
                    userFeedback: note,
                    label: item.wasHelpful ? .confirmed : .correction
                )
            )

            if examples.count >= limit { break }
        }

        return examples
    }

    public func validReviewFeedbackExamples(limit: Int = 20) -> [SessionReviewFeedbackExample] {
        recentReviewFeedback(limit: 200)
            .compactMap { item in
                guard let note = sanitizedFeedbackNote(item.note) else { return nil }
                return SessionReviewFeedbackExample(
                    sessionID: item.sessionID,
                    createdAt: item.createdAt,
                    goal: item.goalSnapshot,
                    reviewSaid: combinedReviewedResponse(from: item),
                    userFeedback: note,
                    label: item.wasHelpful ? .confirmed : .correction
                )
            }
            .dedupedByFeedbackNote()
            .prefix(limit)
            .map { $0 }
    }

    public func saveReviewLearningMemory(_ memory: SessionReviewLearningMemory) throws {
        guard let db else { throw SessionStoreError.unavailable }
        let json = try jsonString(for: memory.learnings)
        try execute(
            db,
            sql: """
            INSERT INTO review_learning_memory (
                id, updated_at, source_feedback_count, learning_json
            ) VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                updated_at = excluded.updated_at,
                source_feedback_count = excluded.source_feedback_count,
                learning_json = excluded.learning_json
            """,
            bind: { statement in
                sqlite3_bind_double(statement, 1, memory.updatedAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 2, Int32(memory.sourceFeedbackCount))
                sqlite3_bind_text(statement, 3, json, -1, SQLITE_TRANSIENT)
            }
        )
    }

    public func reviewLearningMemory() -> SessionReviewLearningMemory? {
        guard
            let db,
            let row = queryRow(db, sql: """
                SELECT updated_at, source_feedback_count, learning_json
                FROM review_learning_memory
                WHERE id = 1
                LIMIT 1
                """),
            let updatedAtValue = row.double("updated_at"),
            let sourceFeedbackCount = row.int("source_feedback_count"),
            let learningJSON = row.string("learning_json"),
            let data = learningJSON.data(using: .utf8)
        else {
            return nil
        }

        let learnings: [String]
        do {
            learnings = try jsonDecoder.decode([String].self, from: data)
        } catch {
            reportStoreIssue("Ignoring malformed review learning memory: \(error.localizedDescription)")
            return nil
        }

        return SessionReviewLearningMemory(
            updatedAt: Date(timeIntervalSince1970: updatedAtValue),
            sourceFeedbackCount: sourceFeedbackCount,
            learnings: learnings
        )
    }

    public func saveSession(
        _ session: StoredSession,
        review: StoredSessionReview?,
        segments: [TimelineSegment],
        rawEventCount: Int
    ) throws {
        guard let db else { throw SessionStoreError.unavailable }
        let labelsJSON = try jsonString(for: session.primaryLabels)

        try execute(
            db,
            sql: """
            INSERT INTO sessions (
                id, goal, started_at, ended_at, verdict, headline, summary, review_status, review_error_message, primary_labels_json, raw_event_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                goal = excluded.goal,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                verdict = excluded.verdict,
                headline = excluded.headline,
                summary = excluded.summary,
                review_status = excluded.review_status,
                review_error_message = excluded.review_error_message,
                primary_labels_json = excluded.primary_labels_json,
                raw_event_count = excluded.raw_event_count
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, session.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, session.goal, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 3, session.startedAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 4, session.endedAt.timeIntervalSince1970)
                bindNullableText(session.verdict?.rawValue, to: statement, index: 5)
                bindNullableText(session.headline, to: statement, index: 6)
                bindNullableText(session.summary, to: statement, index: 7)
                sqlite3_bind_text(statement, 8, session.reviewStatus.rawValue, -1, SQLITE_TRANSIENT)
                bindNullableText(session.reviewErrorMessage, to: statement, index: 9)
                sqlite3_bind_text(statement, 10, labelsJSON, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 11, Int32(rawEventCount))
            }
        )

        try execute(
            db,
            sql: "DELETE FROM session_segments WHERE session_id = ?",
            bind: { statement in
                sqlite3_bind_text(statement, 1, session.id, -1, SQLITE_TRANSIENT)
            }
        )

        for segment in segments {
            let payload = try jsonString(for: segment)
            try execute(
                db,
                sql: """
                INSERT INTO session_segments (
                    id, session_id, start_at, end_at, app_name, primary_label, secondary_label, category, repo_name, file_path, url, domain, confidence, event_count, payload_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bind: { statement in
                    sqlite3_bind_text(statement, 1, segment.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, session.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 3, segment.startAt.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 4, segment.endAt.timeIntervalSince1970)
                    sqlite3_bind_text(statement, 5, segment.appName, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 6, segment.primaryLabel, -1, SQLITE_TRANSIENT)
                    bindNullableText(segment.secondaryLabel, to: statement, index: 7)
                    sqlite3_bind_text(statement, 8, segment.category.rawValue, -1, SQLITE_TRANSIENT)
                    bindNullableText(segment.repoName, to: statement, index: 9)
                    bindNullableText(segment.filePath, to: statement, index: 10)
                    bindNullableText(segment.url, to: statement, index: 11)
                    bindNullableText(segment.domain, to: statement, index: 12)
                    sqlite3_bind_double(statement, 13, segment.confidence)
                    sqlite3_bind_int(statement, 14, Int32(segment.eventCount))
                    sqlite3_bind_text(statement, 15, payload, -1, SQLITE_TRANSIENT)
                }
            )
        }

        try rebuildContextMemory(
            db,
            session: session,
            segments: segments
        )

        if let review {
            let reviewJSON = try jsonString(for: review.review)
            try execute(
                db,
                sql: """
                INSERT INTO session_reviews (
                    session_id, generated_at, provider_title, review_json, debug_prompt, debug_raw_response
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    generated_at = excluded.generated_at,
                    provider_title = excluded.provider_title,
                    review_json = excluded.review_json,
                    debug_prompt = excluded.debug_prompt,
                    debug_raw_response = excluded.debug_raw_response
                """,
                bind: { statement in
                    sqlite3_bind_text(statement, 1, review.sessionID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 2, review.generatedAt.timeIntervalSince1970)
                    sqlite3_bind_text(statement, 3, review.providerTitle, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, reviewJSON, -1, SQLITE_TRANSIENT)
                    bindNullableText(review.debugPrompt, to: statement, index: 5)
                    bindNullableText(review.debugRawResponse, to: statement, index: 6)
                }
            )
        }
    }

    public func sessionHistory(limit: Int = 200) -> [StoredSession] {
        guard let db else { return [] }
        var results: [StoredSession] = []
        guard let statement = prepare(db, sql: """
            SELECT id, goal, started_at, ended_at, verdict, headline, summary, review_status, review_error_message, primary_labels_json
            FROM sessions
            ORDER BY started_at DESC
            LIMIT ?
            """
        ) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = string(from: statement, index: 0),
                let goal = string(from: statement, index: 1),
                let reviewStatusRaw = string(from: statement, index: 7),
                let reviewStatus = ReviewStatus(rawValue: reviewStatusRaw),
                let labelsJSON = string(from: statement, index: 9)
            else {
                reportStoreIssue("Skipping malformed session history row.")
                continue
            }
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let endedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let verdict = string(from: statement, index: 4).flatMap(SessionVerdict.init(rawValue:))
            let headline = string(from: statement, index: 5)
            let summary = string(from: statement, index: 6)
            let reviewErrorMessage = string(from: statement, index: 8)
            let labels: [String]
            do {
                labels = try jsonDecoder.decode([String].self, from: Data(labelsJSON.utf8))
            } catch {
                reportStoreIssue("Skipping session \(id) due to malformed primary labels JSON: \(error.localizedDescription)")
                continue
            }
            results.append(
                StoredSession(
                    id: id,
                    goal: goal,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    verdict: verdict,
                    headline: headline,
                    summary: summary,
                    reviewStatus: reviewStatus,
                    reviewErrorMessage: reviewErrorMessage,
                    primaryLabels: labels
                )
            )
        }

        return results
    }

    public func sessions(overlapping startAt: Date, and endAt: Date, limit: Int = 500) -> [StoredSession] {
        guard let db else { return [] }
        var results: [StoredSession] = []
        guard let statement = prepare(db, sql: """
            SELECT id, goal, started_at, ended_at, verdict, headline, summary, review_status, review_error_message, primary_labels_json
            FROM sessions
            WHERE ended_at > ? AND started_at < ?
            ORDER BY started_at DESC
            LIMIT ?
            """
        ) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, startAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, endAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 3, Int32(limit))

        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = string(from: statement, index: 0),
                let goal = string(from: statement, index: 1),
                let reviewStatusRaw = string(from: statement, index: 7),
                let reviewStatus = ReviewStatus(rawValue: reviewStatusRaw),
                let labelsJSON = string(from: statement, index: 9)
            else {
                reportStoreIssue("Skipping malformed ranged session row.")
                continue
            }
            let startedAtValue = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let endedAtValue = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let verdict = string(from: statement, index: 4).flatMap(SessionVerdict.init(rawValue:))
            let headline = string(from: statement, index: 5)
            let summary = string(from: statement, index: 6)
            let reviewErrorMessage = string(from: statement, index: 8)
            let labels: [String]
            do {
                labels = try jsonDecoder.decode([String].self, from: Data(labelsJSON.utf8))
            } catch {
                reportStoreIssue("Skipping session \(id) due to malformed primary labels JSON: \(error.localizedDescription)")
                continue
            }
            results.append(
                StoredSession(
                    id: id,
                    goal: goal,
                    startedAt: startedAtValue,
                    endedAt: endedAtValue,
                    verdict: verdict,
                    headline: headline,
                    summary: summary,
                    reviewStatus: reviewStatus,
                    reviewErrorMessage: reviewErrorMessage,
                    primaryLabels: labels
                )
            )
        }

        return results
    }

    public func savePeriodicSummary(_ summary: StoredPeriodicSummary) throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(
            db,
            sql: """
            INSERT INTO periodic_summaries (
                id, kind, period_start, period_end, generated_at, provider_title, title, summary, next_step
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(kind, period_start, period_end) DO UPDATE SET
                id = excluded.id,
                generated_at = excluded.generated_at,
                provider_title = excluded.provider_title,
                title = excluded.title,
                summary = excluded.summary,
                next_step = excluded.next_step
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, summary.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, summary.kind.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(statement, 3, summary.periodStart.timeIntervalSince1970)
                sqlite3_bind_double(statement, 4, summary.periodEnd.timeIntervalSince1970)
                sqlite3_bind_double(statement, 5, summary.generatedAt.timeIntervalSince1970)
                sqlite3_bind_text(statement, 6, summary.providerTitle, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 7, summary.title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 8, summary.summary, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 9, summary.nextStep, -1, SQLITE_TRANSIENT)
            }
        )
    }

    public func latestPeriodicSummary(kind: StoredPeriodicSummaryKind) -> StoredPeriodicSummary? {
        guard let db else { return nil }
        guard
            let row = queryRow(
                db,
                sql: """
                SELECT id, kind, period_start, period_end, generated_at, provider_title, title, summary, next_step
                FROM periodic_summaries
                WHERE kind = ?
                ORDER BY period_start DESC, generated_at DESC
                LIMIT 1
                """,
                bind: { sqlite3_bind_text($0, 1, kind.rawValue, -1, SQLITE_TRANSIENT) }
            ),
            let id = row.string("id"),
            let kindRaw = row.string("kind"),
            let storedKind = StoredPeriodicSummaryKind(rawValue: kindRaw),
            let periodStart = row.double("period_start"),
            let periodEnd = row.double("period_end"),
            let generatedAt = row.double("generated_at"),
            let providerTitle = row.string("provider_title"),
            let title = row.string("title"),
            let summary = row.string("summary"),
            let nextStep = row.string("next_step")
        else {
            return nil
        }

        return StoredPeriodicSummary(
            id: id,
            kind: storedKind,
            periodStart: Date(timeIntervalSince1970: periodStart),
            periodEnd: Date(timeIntervalSince1970: periodEnd),
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            providerTitle: providerTitle,
            title: title,
            summary: summary,
            nextStep: nextStep
        )
    }

    public func periodicSummaryHistory(kind: StoredPeriodicSummaryKind, limit: Int = 24) -> [StoredPeriodicSummary] {
        guard let db, limit > 0 else { return [] }
        guard let statement = prepare(db, sql: """
            SELECT id, kind, period_start, period_end, generated_at, provider_title, title, summary, next_step
            FROM periodic_summaries
            WHERE kind = ?
            ORDER BY period_start DESC, generated_at DESC
            LIMIT ?
            """) else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var summaries: [StoredPeriodicSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = string(from: statement, index: 0),
                let kindRaw = string(from: statement, index: 1),
                let storedKind = StoredPeriodicSummaryKind(rawValue: kindRaw),
                let providerTitle = string(from: statement, index: 5),
                let title = string(from: statement, index: 6),
                let summary = string(from: statement, index: 7),
                let nextStep = string(from: statement, index: 8)
            else {
                reportStoreIssue("Skipping malformed periodic summary row.")
                continue
            }

            summaries.append(
                StoredPeriodicSummary(
                    id: id,
                    kind: storedKind,
                    periodStart: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    periodEnd: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                    generatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    providerTitle: providerTitle,
                    title: title,
                    summary: summary,
                    nextStep: nextStep
                )
            )
        }

        return summaries
    }

    public func periodicSummary(kind: StoredPeriodicSummaryKind, periodStart: Date, periodEnd: Date) -> StoredPeriodicSummary? {
        guard let db else { return nil }
        guard
            let row = queryRow(
                db,
                sql: """
                SELECT id, kind, period_start, period_end, generated_at, provider_title, title, summary, next_step
                FROM periodic_summaries
                WHERE kind = ? AND period_start = ? AND period_end = ?
                LIMIT 1
                """,
                bind: { statement in
                    sqlite3_bind_text(statement, 1, kind.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(statement, 2, periodStart.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 3, periodEnd.timeIntervalSince1970)
                }
            ),
            let id = row.string("id"),
            let kindRaw = row.string("kind"),
            let storedKind = StoredPeriodicSummaryKind(rawValue: kindRaw),
            let storedPeriodStart = row.double("period_start"),
            let storedPeriodEnd = row.double("period_end"),
            let generatedAt = row.double("generated_at"),
            let providerTitle = row.string("provider_title"),
            let title = row.string("title"),
            let summary = row.string("summary"),
            let nextStep = row.string("next_step")
        else {
            return nil
        }

        return StoredPeriodicSummary(
            id: id,
            kind: storedKind,
            periodStart: Date(timeIntervalSince1970: storedPeriodStart),
            periodEnd: Date(timeIntervalSince1970: storedPeriodEnd),
            generatedAt: Date(timeIntervalSince1970: generatedAt),
            providerTitle: providerTitle,
            title: title,
            summary: summary,
            nextStep: nextStep
        )
    }

    public func latestSessionDetail() -> StoredSessionDetail? {
        sessionHistory(limit: 1).first.flatMap { sessionDetail(id: $0.id) }
    }

    public func sessionDetail(id: String) -> StoredSessionDetail? {
        guard let session = sessionHistory(limit: 500).first(where: { $0.id == id }) else {
            return nil
        }

        let segments = loadSegments(sessionID: id)
        let review = loadReview(sessionID: id)
        let rawEventCount = loadRawEventCount(sessionID: id) ?? segments.reduce(0) { $0 + $1.eventCount }
        return StoredSessionDetail(session: session, review: review, segments: segments, rawEventCount: rawEventCount)
    }

    public func deleteSession(id: String) throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(db, sql: "DELETE FROM session_review_feedback WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_reviews WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_context_transitions WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_context_surfaces WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_segments WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM sessions WHERE id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
    }

    public func contextPatternSnapshot(
        goal _: String,
        excludingSessionID: String? = nil,
        limit: Int = 3
    ) -> ContextPatternSnapshot? {
        guard let db else { return nil }

        let sessionCountSQL: String
        if excludingSessionID == nil {
            sessionCountSQL = """
            SELECT COUNT(DISTINCT s.id) AS session_count
            FROM sessions s
            JOIN session_context_surfaces scs ON scs.session_id = s.id
            """
        } else {
            sessionCountSQL = """
            SELECT COUNT(DISTINCT s.id) AS session_count
            FROM sessions s
            JOIN session_context_surfaces scs ON scs.session_id = s.id
            WHERE s.id != ?
            """
        }

        let sessionCountRow = queryRow(db, sql: sessionCountSQL, bind: { statement in
            if let excludingSessionID {
                sqlite3_bind_text(statement, 1, excludingSessionID, -1, SQLITE_TRANSIENT)
            }
        })
        let sessionCount = sessionCountRow?.int("session_count") ?? 0
        guard sessionCount > 0 else { return nil }

        func rankedSurfaceLines(for roles: [SessionSegmentRole]) -> [String] {
            let placeholders = roles.enumerated().map { _ in "?" }.joined(separator: ", ")
            let sql: String
            if excludingSessionID == nil {
                sql = """
                SELECT cn.label, SUM(scs.seconds) AS total_seconds, COUNT(DISTINCT scs.session_id) AS session_count
                FROM session_context_surfaces scs
                JOIN sessions s ON s.id = scs.session_id
                JOIN context_nodes cn ON cn.id = scs.node_id
                WHERE scs.role IN (\(placeholders))
                GROUP BY scs.node_id
                ORDER BY total_seconds DESC, session_count DESC, cn.label ASC
                LIMIT ?
                """
            } else {
                sql = """
                SELECT cn.label, SUM(scs.seconds) AS total_seconds, COUNT(DISTINCT scs.session_id) AS session_count
                FROM session_context_surfaces scs
                JOIN sessions s ON s.id = scs.session_id
                JOIN context_nodes cn ON cn.id = scs.node_id
                WHERE s.id != ? AND scs.role IN (\(placeholders))
                GROUP BY scs.node_id
                ORDER BY total_seconds DESC, session_count DESC, cn.label ASC
                LIMIT ?
                """
            }

            guard let statement = prepare(db, sql: sql) else { return [] }
            defer { sqlite3_finalize(statement) }

            var bindIndex: Int32 = 1
            if let excludingSessionID {
                sqlite3_bind_text(statement, bindIndex, excludingSessionID, -1, SQLITE_TRANSIENT)
                bindIndex += 1
            }
            for role in roles {
                sqlite3_bind_text(statement, bindIndex, role.rawValue, -1, SQLITE_TRANSIENT)
                bindIndex += 1
            }
            sqlite3_bind_int(statement, bindIndex, Int32(limit))

            var lines: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let label = string(from: statement, index: 0) ?? "Unknown"
                let totalSeconds = Int(sqlite3_column_int(statement, 1))
                let surfaceSessionCount = Int(sqlite3_column_int(statement, 2))
                lines.append("\(label) — \(naturalDurationLabel(for: totalSeconds)) across \(surfaceSessionCount) session\(surfaceSessionCount == 1 ? "" : "s")")
            }
            return lines
        }

        let transitionsSQL: String
        if excludingSessionID == nil {
            transitionsSQL = """
            SELECT from_node.label, to_node.label, SUM(sct.count) AS transition_count
            FROM session_context_transitions sct
            JOIN sessions s ON s.id = sct.session_id
            JOIN context_nodes from_node ON from_node.id = sct.from_node_id
            JOIN context_nodes to_node ON to_node.id = sct.to_node_id
            GROUP BY sct.from_node_id, sct.to_node_id
            ORDER BY transition_count DESC, from_node.label ASC, to_node.label ASC
            LIMIT ?
            """
        } else {
            transitionsSQL = """
            SELECT from_node.label, to_node.label, SUM(sct.count) AS transition_count
            FROM session_context_transitions sct
            JOIN sessions s ON s.id = sct.session_id
            JOIN context_nodes from_node ON from_node.id = sct.from_node_id
            JOIN context_nodes to_node ON to_node.id = sct.to_node_id
            WHERE s.id != ?
            GROUP BY sct.from_node_id, sct.to_node_id
            ORDER BY transition_count DESC, from_node.label ASC, to_node.label ASC
            LIMIT ?
            """
        }

        var commonTransitions: [String] = []
        if let statement = prepare(db, sql: transitionsSQL) {
            defer { sqlite3_finalize(statement) }
            if let excludingSessionID {
                sqlite3_bind_text(statement, 1, excludingSessionID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 2, Int32(limit))
            } else {
                sqlite3_bind_int(statement, 1, Int32(limit))
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                let from = string(from: statement, index: 0) ?? "Unknown"
                let to = string(from: statement, index: 1) ?? "Unknown"
                let count = Int(sqlite3_column_int(statement, 2))
                commonTransitions.append("\(from) -> \(to) (\(count)x)")
            }
        }

        return ContextPatternSnapshot(
            sessionCount: sessionCount,
            alignedSurfaces: rankedSurfaceLines(for: [.direct, .support]),
            driftSurfaces: rankedSurfaceLines(for: [.drift]),
            commonTransitions: commonTransitions
        )
    }

    private func loadSegments(sessionID: String) -> [TimelineSegment] {
        guard let db else { return [] }
        var segments: [TimelineSegment] = []
        guard let statement = prepare(db, sql: """
            SELECT payload_json
            FROM session_segments
            WHERE session_id = ?
            ORDER BY start_at ASC
            """
        ) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, SQLITE_TRANSIENT)

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let json = string(from: statement, index: 0),
                  let data = json.data(using: .utf8) else {
                reportStoreIssue("Skipping malformed session segment payload for session \(sessionID).")
                continue
            }

            do {
                segments.append(try jsonDecoder.decode(TimelineSegment.self, from: data))
            } catch {
                reportStoreIssue("Skipping malformed session segment for session \(sessionID): \(error.localizedDescription)")
            }
        }
        return segments
    }

    private func loadReview(sessionID: String) -> StoredSessionReview? {
        guard
            let db,
            let statement = prepare(db, sql: """
                SELECT generated_at, provider_title, review_json, debug_prompt, debug_raw_response
                FROM session_reviews
                WHERE session_id = ?
                LIMIT 1
                """)
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sessionID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let generatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
        guard let providerTitle = string(from: statement, index: 1) else {
            reportStoreIssue("Skipping malformed review row for session \(sessionID): missing provider title.")
            return nil
        }
        guard
            let json = string(from: statement, index: 2),
            let data = json.data(using: .utf8)
        else {
            reportStoreIssue("Skipping malformed review row for session \(sessionID): missing review payload.")
            return nil
        }
        let review: SessionReview
        do {
            review = try jsonDecoder.decode(SessionReview.self, from: data)
        } catch {
            reportStoreIssue("Skipping malformed review for session \(sessionID): \(error.localizedDescription)")
            return nil
        }
        return StoredSessionReview(
            sessionID: sessionID,
            generatedAt: generatedAt,
            providerTitle: providerTitle,
            review: review,
            debugPrompt: string(from: statement, index: 3),
            debugRawResponse: string(from: statement, index: 4)
        )
    }

    private func loadRawEventCount(sessionID: String) -> Int? {
        guard
            let db,
            let row = queryRow(db, sql: "SELECT raw_event_count FROM sessions WHERE id = ?", bind: {
                sqlite3_bind_text($0, 1, sessionID, -1, SQLITE_TRANSIENT)
            }),
            let count = row.int("raw_event_count")
        else {
            return nil
        }
        return count
    }

    private func fetchEvents(
        sql: String,
        bind: ((OpaquePointer?) -> Void)? = nil
    ) -> [ActivityEvent] {
        guard let db, let statement = prepare(db, sql: sql) else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        bind?(statement)

        var events: [ActivityEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let json = string(from: statement, index: 0),
                  let data = json.data(using: .utf8) else {
                reportStoreIssue("Skipping malformed raw event payload.")
                continue
            }

            do {
                events.append(try jsonDecoder.decode(ActivityEvent.self, from: data))
            } catch {
                reportStoreIssue("Skipping malformed raw event: \(error.localizedDescription)")
            }
        }
        return events
    }

    private func openDatabase() {
        do {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            let storeError = SessionStoreError.sqlite(message: "Driftly could not prepare its local database directory: \(error.localizedDescription)")
            startupError = storeError
            reportStoreIssue(storeError.localizedDescription)
            db = nil
            return
        }

        guard sqlite3_open(path.path, &db) == SQLITE_OK else {
            let message = currentSQLiteError(on: db)
            if let db {
                sqlite3_close(db)
            }
            startupError = .sqlite(message: message)
            reportStoreIssue(message)
            db = nil
            return
        }

        startupError = nil
        sqlite3_busy_timeout(db, 2_500)
        _ = sqlite3_exec(db, "PRAGMA foreign_keys = ON", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        _ = sqlite3_exec(db, "PRAGMA synchronous = NORMAL", nil, nil, nil)
    }

    private func createSchema() {
        guard let db else { return }
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS settings (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                json TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS raw_events (
                id TEXT PRIMARY KEY,
                occurred_at REAL NOT NULL,
                source TEXT NOT NULL,
                kind TEXT NOT NULL,
                app_name TEXT,
                bundle_id TEXT,
                domain TEXT,
                working_directory TEXT,
                payload_json TEXT NOT NULL
            )
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_raw_events_occurred_at
            ON raw_events(occurred_at)
            """,
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                goal TEXT NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL,
                verdict TEXT,
                headline TEXT,
                summary TEXT,
                review_status TEXT NOT NULL,
                review_error_message TEXT,
                primary_labels_json TEXT NOT NULL DEFAULT '[]',
                raw_event_count INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_sessions_started_at
            ON sessions(started_at DESC)
            """,
            """
            CREATE TABLE IF NOT EXISTS session_segments (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                start_at REAL NOT NULL,
                end_at REAL NOT NULL,
                app_name TEXT NOT NULL,
                primary_label TEXT NOT NULL,
                secondary_label TEXT,
                category TEXT NOT NULL,
                repo_name TEXT,
                file_path TEXT,
                url TEXT,
                domain TEXT,
                confidence REAL NOT NULL,
                event_count INTEGER NOT NULL,
                payload_json TEXT NOT NULL,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_session_segments_session_id
            ON session_segments(session_id, start_at)
            """,
            """
            CREATE TABLE IF NOT EXISTS session_reviews (
                session_id TEXT PRIMARY KEY,
                generated_at REAL NOT NULL,
                provider_title TEXT NOT NULL,
                review_json TEXT NOT NULL,
                debug_prompt TEXT,
                debug_raw_response TEXT,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS session_review_feedback (
                session_id TEXT PRIMARY KEY,
                created_at REAL NOT NULL,
                was_helpful INTEGER NOT NULL,
                note TEXT,
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS review_learning_memory (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                updated_at REAL NOT NULL,
                source_feedback_count INTEGER NOT NULL,
                learning_json TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS context_nodes (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                label TEXT NOT NULL,
                normalized_label TEXT NOT NULL UNIQUE,
                app_name TEXT,
                domain TEXT,
                repo_name TEXT,
                file_path TEXT,
                first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS session_context_surfaces (
                session_id TEXT NOT NULL,
                node_id TEXT NOT NULL,
                role TEXT NOT NULL,
                seconds INTEGER NOT NULL,
                share REAL NOT NULL,
                first_position INTEGER NOT NULL,
                last_position INTEGER NOT NULL,
                PRIMARY KEY(session_id, node_id, role),
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(node_id) REFERENCES context_nodes(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_session_context_surfaces_session_id
            ON session_context_surfaces(session_id)
            """,
            """
            CREATE TABLE IF NOT EXISTS session_context_transitions (
                session_id TEXT NOT NULL,
                from_node_id TEXT NOT NULL,
                to_node_id TEXT NOT NULL,
                relation TEXT NOT NULL,
                count INTEGER NOT NULL,
                last_seen_at REAL NOT NULL,
                PRIMARY KEY(session_id, from_node_id, to_node_id, relation),
                FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
                FOREIGN KEY(from_node_id) REFERENCES context_nodes(id) ON DELETE CASCADE,
                FOREIGN KEY(to_node_id) REFERENCES context_nodes(id) ON DELETE CASCADE
            )
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_session_context_transitions_session_id
            ON session_context_transitions(session_id)
            """,
            """
            CREATE TABLE IF NOT EXISTS periodic_summaries (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                period_start REAL NOT NULL,
                period_end REAL NOT NULL,
                generated_at REAL NOT NULL,
                provider_title TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT NOT NULL,
                next_step TEXT NOT NULL
            )
            """,
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_periodic_summaries_kind_period
            ON periodic_summaries(kind, period_start, period_end)
            """,
        ]

        for statement in statements {
            _ = sqlite3_exec(db, statement, nil, nil, nil)
        }
        _ = sqlite3_exec(db, "DROP INDEX IF EXISTS idx_sessions_goal_mode", nil, nil, nil)

        ensureColumn(on: db, table: "session_review_feedback", name: "goal_snapshot", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(on: db, table: "session_review_feedback", name: "review_headline_snapshot", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(on: db, table: "session_review_feedback", name: "review_summary_snapshot", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumn(on: db, table: "session_review_feedback", name: "review_takeaway_snapshot", definition: "TEXT")
        ensureColumn(on: db, table: "sessions", name: "review_error_message", definition: "TEXT")
    }
}

private extension SessionStore {
    func rebuildContextMemory(
        _ db: OpaquePointer?,
        session: StoredSession,
        segments: [TimelineSegment]
    ) throws {
        guard let db else { throw SessionStoreError.unavailable }

        try execute(db, sql: "DELETE FROM session_context_transitions WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, session.id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_context_surfaces WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, session.id, -1, SQLITE_TRANSIENT) })

        guard !segments.isEmpty else { return }

        let observedSegments = TimelineDeriver.observeSegments(segments, goal: session.goal)
        let totalSeconds = max(segments.reduce(0) { $0 + max(Int($1.endAt.timeIntervalSince($1.startAt).rounded()), 1) }, 1)

        struct SurfaceAggregate {
            var node: ContextNode
            var role: SessionSegmentRole
            var seconds: Int
            var firstPosition: Int
            var lastPosition: Int
        }

        var surfaceAggregates: [String: SurfaceAggregate] = [:]
        var transitionCounts: [String: SessionContextTransition] = [:]
        var orderedNodeIDs: [String] = []

        for (index, observed) in observedSegments.enumerated() {
            let node = contextNode(for: observed.segment)
            try upsertContextNode(node, on: db)

            let seconds = max(Int(observed.segment.endAt.timeIntervalSince(observed.segment.startAt).rounded()), 1)
            let key = "\(node.id)|\(observed.role.rawValue)"
            if var aggregate = surfaceAggregates[key] {
                aggregate.seconds += seconds
                aggregate.lastPosition = index
                surfaceAggregates[key] = aggregate
            } else {
                surfaceAggregates[key] = SurfaceAggregate(
                    node: node,
                    role: observed.role,
                    seconds: seconds,
                    firstPosition: index,
                    lastPosition: index
                )
            }

            if orderedNodeIDs.last != node.id {
                orderedNodeIDs.append(node.id)
            }
        }

        for aggregate in surfaceAggregates.values {
            let share = Double(aggregate.seconds) / Double(totalSeconds)
            try execute(
                db,
                sql: """
                INSERT INTO session_context_surfaces (
                    session_id, node_id, role, seconds, share, first_position, last_position
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bind: { statement in
                    sqlite3_bind_text(statement, 1, session.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, aggregate.node.id, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, aggregate.role.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 4, Int32(aggregate.seconds))
                    sqlite3_bind_double(statement, 5, share)
                    sqlite3_bind_int(statement, 6, Int32(aggregate.firstPosition))
                    sqlite3_bind_int(statement, 7, Int32(aggregate.lastPosition))
                }
            )
        }

        for pair in zip(orderedNodeIDs, orderedNodeIDs.dropFirst()) {
            guard pair.0 != pair.1 else { continue }
            let relation = "switches_to"
            let key = "\(pair.0)|\(pair.1)|\(relation)"
            if var transition = transitionCounts[key] {
                transition = SessionContextTransition(
                    sessionID: transition.sessionID,
                    fromNodeID: transition.fromNodeID,
                    toNodeID: transition.toNodeID,
                    relation: transition.relation,
                    count: transition.count + 1,
                    lastSeenAt: session.endedAt
                )
                transitionCounts[key] = transition
            } else {
                transitionCounts[key] = SessionContextTransition(
                    sessionID: session.id,
                    fromNodeID: pair.0,
                    toNodeID: pair.1,
                    relation: relation,
                    count: 1,
                    lastSeenAt: session.endedAt
                )
            }
        }

        for transition in transitionCounts.values {
            try execute(
                db,
                sql: """
                INSERT INTO session_context_transitions (
                    session_id, from_node_id, to_node_id, relation, count, last_seen_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                bind: { statement in
                    sqlite3_bind_text(statement, 1, transition.sessionID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 2, transition.fromNodeID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 3, transition.toNodeID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(statement, 4, transition.relation, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(statement, 5, Int32(transition.count))
                    sqlite3_bind_double(statement, 6, transition.lastSeenAt.timeIntervalSince1970)
                }
            )
        }
    }

    func upsertContextNode(_ node: ContextNode, on db: OpaquePointer?) throws {
        guard let db else { throw SessionStoreError.unavailable }
        try execute(
            db,
            sql: """
            INSERT INTO context_nodes (
                id, kind, label, normalized_label, app_name, domain, repo_name, file_path, first_seen_at, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(normalized_label) DO UPDATE SET
                label = excluded.label,
                app_name = COALESCE(excluded.app_name, context_nodes.app_name),
                domain = COALESCE(excluded.domain, context_nodes.domain),
                repo_name = COALESCE(excluded.repo_name, context_nodes.repo_name),
                file_path = COALESCE(excluded.file_path, context_nodes.file_path),
                last_seen_at = excluded.last_seen_at
            """,
            bind: { statement in
                sqlite3_bind_text(statement, 1, node.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, node.kind.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, node.label, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 4, node.normalizedLabel, -1, SQLITE_TRANSIENT)
                bindNullableText(node.appName, to: statement, index: 5)
                bindNullableText(node.domain, to: statement, index: 6)
                bindNullableText(node.repoName, to: statement, index: 7)
                bindNullableText(node.filePath, to: statement, index: 8)
                sqlite3_bind_double(statement, 9, node.firstSeenAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 10, node.lastSeenAt.timeIntervalSince1970)
            }
        )
    }

    func contextNode(for segment: TimelineSegment) -> ContextNode {
        let kind: ContextNodeKind
        let label: String

        if let repoName = segment.repoName?.trimmingCharacters(in: .whitespacesAndNewlines), !repoName.isEmpty {
            kind = .repo
            label = repoName
        } else if let filePath = segment.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !filePath.isEmpty {
            kind = .file
            label = URL(fileURLWithPath: filePath).lastPathComponent
        } else if let domain = segment.domain?.trimmingCharacters(in: .whitespacesAndNewlines), !domain.isEmpty {
            kind = .site
            label = segment.primaryLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? domain : segment.primaryLabel
        } else {
            kind = .app
            label = segment.primaryLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? segment.appName : segment.primaryLabel
        }

        let normalizedLabel = "\(kind.rawValue):\(normalizeContextLabel(label))"
        return ContextNode(
            id: normalizedLabel,
            kind: kind,
            label: label,
            normalizedLabel: normalizedLabel,
            appName: segment.appName,
            domain: segment.domain,
            repoName: segment.repoName,
            filePath: segment.filePath,
            firstSeenAt: segment.startAt,
            lastSeenAt: segment.endAt
        )
    }
}

private func normalizeContextLabel(_ label: String) -> String {
    label
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

public enum SessionStoreError: Error, LocalizedError {
    case unavailable
    case sqlite(message: String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Driftly could not open its local database."
        case let .sqlite(message):
            return message
        }
    }
}

private let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

private let jsonDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private let settingsDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

private func jsonString<T: Encodable>(for value: T) throws -> String {
    let data = try jsonEncoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw SessionStoreError.sqlite(message: "Failed to encode JSON string.")
    }
    return string
}

private func execute(
    _ db: OpaquePointer,
    sql: String,
    bind: ((OpaquePointer?) -> Void)? = nil
) throws {
    guard let statement = prepare(db, sql: sql) else {
        throw SessionStoreError.sqlite(message: currentSQLiteError(on: db))
    }
    defer { sqlite3_finalize(statement) }
    bind?(statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE else {
        throw SessionStoreError.sqlite(message: currentSQLiteError(on: db))
    }
}

private func executeReturningBool(
    _ db: OpaquePointer,
    sql: String,
    bind: ((OpaquePointer?) -> Void)? = nil
) throws -> Bool {
    guard let statement = prepare(db, sql: sql) else {
        throw SessionStoreError.sqlite(message: currentSQLiteError(on: db))
    }
    defer { sqlite3_finalize(statement) }
    bind?(statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE else {
        throw SessionStoreError.sqlite(message: currentSQLiteError(on: db))
    }
    return sqlite3_changes(db) > 0
}

private func prepare(_ db: OpaquePointer, sql: String) -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        return nil
    }
    return statement
}

private enum SQLiteValue {
    case integer(Int)
    case real(Double)
    case text(String)
    case null

    var intValue: Int? {
        switch self {
        case let .integer(value):
            return value
        case let .real(value):
            return Int(exactly: value)
        case .text, .null:
            return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .integer(value):
            return Double(value)
        case let .real(value):
            return value
        case .text, .null:
            return nil
        }
    }

    var stringValue: String? {
        switch self {
        case let .text(value):
            return value
        case .integer, .real, .null:
            return nil
        }
    }
}

private struct SQLiteRow {
    private let values: [String: SQLiteValue]

    init(values: [String: SQLiteValue]) {
        self.values = values
    }

    func int(_ key: String) -> Int? {
        values[key]?.intValue
    }

    func double(_ key: String) -> Double? {
        values[key]?.doubleValue
    }

    func string(_ key: String) -> String? {
        values[key]?.stringValue
    }
}

private func queryRow(
    _ db: OpaquePointer,
    sql: String,
    bind: ((OpaquePointer?) -> Void)? = nil
) -> SQLiteRow? {
    guard let statement = prepare(db, sql: sql) else {
        return nil
    }
    defer { sqlite3_finalize(statement) }
    bind?(statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

    var result: [String: SQLiteValue] = [:]
    let count = sqlite3_column_count(statement)
    for index in 0..<count {
        let key = String(cString: sqlite3_column_name(statement, index))
        let type = sqlite3_column_type(statement, index)
        switch type {
        case SQLITE_INTEGER:
            result[key] = .integer(Int(sqlite3_column_int64(statement, index)))
        case SQLITE_FLOAT:
            result[key] = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            if let value = string(from: statement, index: index) {
                result[key] = .text(value)
            } else {
                result[key] = .null
            }
        default:
            result[key] = .null
        }
    }
    return SQLiteRow(values: result)
}

private func string(from statement: OpaquePointer?, index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: pointer)
}

private func bindNullableText(_ value: String?, to statement: OpaquePointer?, index: Int32) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func currentSQLiteError(on db: OpaquePointer?) -> String {
    guard let db, let error = sqlite3_errmsg(db) else {
        return "Unknown SQLite error."
    }
    return String(cString: error)
}

private func reportStoreIssue(_ message: String?) {
    guard let message else { return }
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    fputs("SessionStore: \(trimmed)\n", stderr)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func ensureColumn(on db: OpaquePointer?, table tableName: String, name: String, definition: String) {
    guard let db else { return }
    guard !table(tableName, hasColumn: name, on: db) else { return }
    _ = sqlite3_exec(db, "ALTER TABLE \(tableName) ADD COLUMN \(name) \(definition)", nil, nil, nil)
}

private func table(_ table: String, hasColumn name: String, on db: OpaquePointer?) -> Bool {
    guard let db, let statement = prepare(db, sql: "PRAGMA table_info(\(table))") else {
        return false
    }
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
        if string(from: statement, index: 1) == name {
            return true
        }
    }
    return false
}

private func sanitizedFeedbackNote(_ note: String?) -> String? {
    guard let note else { return nil }
    let collapsed = note
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard collapsed.count >= 8 else { return nil }
    let lowered = collapsed.lowercased()
    let ignored = Set(["ok", "okay", "good", "bad", "wrong", "idk", "nah", "no", "yes"])
    return ignored.contains(lowered) ? nil : collapsed
}

private func combinedReviewedResponse(from feedback: SessionReviewFeedback) -> String {
    let parts = [
        feedback.reviewHeadlineSnapshot.trimmingCharacters(in: .whitespacesAndNewlines),
        feedback.reviewSummarySnapshot.trimmingCharacters(in: .whitespacesAndNewlines),
        feedback.reviewTakeawaySnapshot?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
    ].filter { !$0.isEmpty }
    return parts.joined(separator: " ")
}

private extension Array {
    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == SessionReviewFeedbackExample {
    func dedupedByFeedbackNote() -> [SessionReviewFeedbackExample] {
        var seen: Set<String> = []
        var result: [SessionReviewFeedbackExample] = []

        for item in self {
            let key = item.userFeedback.lowercased()
            if seen.insert(key).inserted {
                result.append(item)
            }
        }

        return result
    }
}

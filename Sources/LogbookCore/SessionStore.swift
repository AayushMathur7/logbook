import Foundation
import SQLite3

public final class SessionStore {
    private var db: OpaquePointer?
    private let path: URL

    public init(path: URL = LogbookPaths.databaseURL) {
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
            let json = row["json"] as? String,
            let data = json.data(using: .utf8),
            let settings = try? settingsDecoder.decode(CaptureSettings.self, from: data)
        else {
            return .default
        }

        return settings
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
                id, goal, started_at, ended_at, verdict, headline, summary, review_status, primary_labels_json, raw_event_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                goal = excluded.goal,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                verdict = excluded.verdict,
                headline = excluded.headline,
                summary = excluded.summary,
                review_status = excluded.review_status,
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
                sqlite3_bind_text(statement, 9, labelsJSON, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 10, Int32(rawEventCount))
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
            SELECT id, goal, started_at, ended_at, verdict, headline, summary, review_status, primary_labels_json
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
            let id = string(from: statement, index: 0) ?? UUID().uuidString
            let goal = string(from: statement, index: 1) ?? "Untitled Session"
            let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let endedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            let verdict = string(from: statement, index: 4).flatMap(SessionVerdict.init(rawValue:))
            let headline = string(from: statement, index: 5)
            let summary = string(from: statement, index: 6)
            let reviewStatus = string(from: statement, index: 7).flatMap(ReviewStatus.init(rawValue:)) ?? .none
            let labelsJSON = string(from: statement, index: 8) ?? "[]"
            let labels = (try? jsonDecoder.decode([String].self, from: Data(labelsJSON.utf8))) ?? []
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
                    primaryLabels: labels
                )
            )
        }

        return results
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
        try execute(db, sql: "DELETE FROM session_reviews WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM session_segments WHERE session_id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
        try execute(db, sql: "DELETE FROM sessions WHERE id = ?", bind: { sqlite3_bind_text($0, 1, id, -1, SQLITE_TRANSIENT) })
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
            if let json = string(from: statement, index: 0),
               let data = json.data(using: .utf8),
               let segment = try? jsonDecoder.decode(TimelineSegment.self, from: data) {
                segments.append(segment)
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
        let providerTitle = string(from: statement, index: 1) ?? "Ollama"
        guard
            let json = string(from: statement, index: 2),
            let data = json.data(using: .utf8),
            let review = try? jsonDecoder.decode(SessionReview.self, from: data)
        else {
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
            let count = row["raw_event_count"] as? Int
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
            if let json = string(from: statement, index: 0),
               let data = json.data(using: .utf8),
               let event = try? jsonDecoder.decode(ActivityEvent.self, from: data) {
                events.append(event)
            }
        }
        return events
    }

    private func openDatabase() {
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(path.path, &db) == SQLITE_OK else {
            if let db {
                sqlite3_close(db)
            }
            db = nil
            return
        }

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
        ]

        for statement in statements {
            _ = sqlite3_exec(db, statement, nil, nil, nil)
        }
    }
}

public enum SessionStoreError: Error {
    case unavailable
    case sqlite(message: String)
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

private func queryRow(
    _ db: OpaquePointer,
    sql: String,
    bind: ((OpaquePointer?) -> Void)? = nil
) -> [String: Any]? {
    guard let statement = prepare(db, sql: sql) else {
        return nil
    }
    defer { sqlite3_finalize(statement) }
    bind?(statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

    var result: [String: Any] = [:]
    let count = sqlite3_column_count(statement)
    for index in 0..<count {
        let key = String(cString: sqlite3_column_name(statement, index))
        let type = sqlite3_column_type(statement, index)
        switch type {
        case SQLITE_INTEGER:
            result[key] = Int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            result[key] = sqlite3_column_double(statement, index)
        case SQLITE_TEXT:
            result[key] = string(from: statement, index: index)
        default:
            result[key] = nil as String?
        }
    }
    return result
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

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension Array {
    var nonEmpty: Self? {
        isEmpty ? nil : self
    }
}

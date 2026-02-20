import Foundation
import SQLite3

final class ClipboardDatabase {
    private let dbPath: String
    private var db: OpaquePointer?

    init(baseDirectory: URL? = nil) {
        let appSupport = baseDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("CBManager", isDirectory: true)

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        dbPath = appSupport.appendingPathComponent("clipboard.sqlite").path

        openDatabase()
        createSchema()
        migrateIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadEntries(limit: Int) -> [ClipboardEntry] {
        let sql = """
        SELECT id, created_at, source_app, kind, content, image_path, ocr_text, ocr_pending,
               ai_title, ai_title_pending
        FROM clipboard_entries
        ORDER BY created_at DESC
        LIMIT ?;
        """

        guard let statement = prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var result: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = string(at: 0, from: statement) ?? UUID().uuidString
            let createdAt = sqlite3_column_double(statement, 1)
            let sourceApp = string(at: 2, from: statement)
            let kindString = string(at: 3, from: statement) ?? ClipboardEntry.Kind.text.rawValue
            let content = string(at: 4, from: statement) ?? ""
            let imagePath = string(at: 5, from: statement)
            let ocrText = string(at: 6, from: statement) ?? ""
            let isPending = sqlite3_column_int(statement, 7) != 0
            let aiTitle = string(at: 8, from: statement) ?? ""
            let aiTitlePending = sqlite3_column_int(statement, 9) != 0

            let kind = ClipboardEntry.Kind(rawValue: kindString) ?? .text
            result.append(
                ClipboardEntry(
                    id: id,
                    content: content,
                    date: Date(timeIntervalSince1970: createdAt),
                    sourceApp: sourceApp,
                    kind: kind,
                    imagePath: imagePath,
                    ocrText: ocrText,
                    isOCRPending: isPending,
                    aiTitle: aiTitle,
                    isAITitlePending: aiTitlePending
                )
            )
        }

        return result
    }

    func insert(_ entry: ClipboardEntry) {
        let sql = """
        INSERT OR REPLACE INTO clipboard_entries
        (id, created_at, source_app, kind, content, image_path, ocr_text, ocr_pending, ai_title, ai_title_pending)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, entry.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, entry.date.timeIntervalSince1970)
        sqlite3_bind_nullable_text(statement, 3, entry.sourceApp)
        sqlite3_bind_text(statement, 4, entry.kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, entry.content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_nullable_text(statement, 6, entry.imagePath)
        sqlite3_bind_text(statement, 7, entry.ocrText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 8, entry.isOCRPending ? 1 : 0)
        sqlite3_bind_text(statement, 9, entry.aiTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 10, entry.isAITitlePending ? 1 : 0)

        sqlite3_step(statement)
    }

    func updateOCR(id: String, ocrText: String, isPending: Bool) {
        let sql = "UPDATE clipboard_entries SET ocr_text = ?, ocr_pending = ? WHERE id = ?;"
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, ocrText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, isPending ? 1 : 0)
        sqlite3_bind_text(statement, 3, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func updateAITitle(id: String, aiTitle: String, isPending: Bool) {
        let sql = "UPDATE clipboard_entries SET ai_title = ?, ai_title_pending = ? WHERE id = ?;"
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, aiTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, isPending ? 1 : 0)
        sqlite3_bind_text(statement, 3, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    func delete(id: String) {
        let sql = "DELETE FROM clipboard_entries WHERE id = ?;"
        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(statement)
    }

    /// Delete entries older than the given date. Returns the deleted entries for cleanup.
    func deleteOlderThan(_ date: Date) -> [ClipboardEntry] {
        let cutoff = date.timeIntervalSince1970

        // First, load the entries that will be deleted so callers can clean up image files.
        let selectSQL = """
        SELECT id, created_at, source_app, kind, content, image_path, ocr_text, ocr_pending,
               ai_title, ai_title_pending
        FROM clipboard_entries
        WHERE created_at < ?
        ORDER BY created_at DESC;
        """
        var removed: [ClipboardEntry] = []
        if let selectStmt = prepare(selectSQL) {
            defer { sqlite3_finalize(selectStmt) }
            sqlite3_bind_double(selectStmt, 1, cutoff)

            while sqlite3_step(selectStmt) == SQLITE_ROW {
                let id = string(at: 0, from: selectStmt) ?? UUID().uuidString
                let createdAt = sqlite3_column_double(selectStmt, 1)
                let sourceApp = string(at: 2, from: selectStmt)
                let kindString = string(at: 3, from: selectStmt) ?? ClipboardEntry.Kind.text.rawValue
                let content = string(at: 4, from: selectStmt) ?? ""
                let imagePath = string(at: 5, from: selectStmt)
                let ocrText = string(at: 6, from: selectStmt) ?? ""
                let isPending = sqlite3_column_int(selectStmt, 7) != 0
                let aiTitle = string(at: 8, from: selectStmt) ?? ""
                let aiTitlePending = sqlite3_column_int(selectStmt, 9) != 0

                let kind = ClipboardEntry.Kind(rawValue: kindString) ?? .text
                removed.append(ClipboardEntry(
                    id: id,
                    content: content,
                    date: Date(timeIntervalSince1970: createdAt),
                    sourceApp: sourceApp,
                    kind: kind,
                    imagePath: imagePath,
                    ocrText: ocrText,
                    isOCRPending: isPending,
                    aiTitle: aiTitle,
                    isAITitlePending: aiTitlePending
                ))
            }
        }

        // Now delete them.
        let deleteSQL = "DELETE FROM clipboard_entries WHERE created_at < ?;"
        if let deleteStmt = prepare(deleteSQL) {
            defer { sqlite3_finalize(deleteStmt) }
            sqlite3_bind_double(deleteStmt, 1, cutoff)
            sqlite3_step(deleteStmt)
        }

        return removed
    }

    func prune(limit: Int) {
        let sql = """
        DELETE FROM clipboard_entries
        WHERE id NOT IN (
            SELECT id FROM clipboard_entries
            ORDER BY created_at DESC
            LIMIT ?
        );
        """

        guard let statement = prepare(sql) else { return }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_step(statement)
    }

    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            db = nil
            return
        }
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_entries (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            source_app TEXT,
            kind TEXT NOT NULL,
            content TEXT,
            image_path TEXT,
            ocr_text TEXT,
            ocr_pending INTEGER NOT NULL DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_clipboard_entries_created_at ON clipboard_entries(created_at DESC);
        """

        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func migrateIfNeeded() {
        _ = sqlite3_exec(db, "ALTER TABLE clipboard_entries ADD COLUMN ocr_pending INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE clipboard_entries ADD COLUMN ai_title TEXT NOT NULL DEFAULT '';", nil, nil, nil)
        _ = sqlite3_exec(db, "ALTER TABLE clipboard_entries ADD COLUMN ai_title_pending INTEGER NOT NULL DEFAULT 0;", nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        return statement
    }

    private func string(at index: Int32, from statement: OpaquePointer?) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
}

private extension OpaquePointer {
    static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }
}

private let SQLITE_TRANSIENT = OpaquePointer.transient

private func sqlite3_bind_nullable_text(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

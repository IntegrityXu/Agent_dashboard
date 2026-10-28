import Foundation
import StatusBoardSQLite

enum DesktopFailure: Error { case unavailable, unsupported, unsafePath, timeout, identityChanged }

struct Inventory {
    struct Activity: Equatable { let recency: Int64; let updated: Int64 }
    let ids: [String]
    let activity: [String: Activity]
    let total: Int
    let unassigned: Int
    var titles: [String: String] = [:]
}

struct LocalInventory {
    let path: String
    func read(account: String) throws -> Inventory {
        let connection = try ReadOnlyStore(path: path, busyTimeout: 200)
        defer { connection.close() }
        let db = connection.db
        // Codex displays `name`; legacy `title` can contain the entire first prompt.
        // Never use `title` or message content as a display-name fallback.
        let sql = """
        SELECT t.id, t.creator_account_id, t.source, t.recency_at_ms, t.updated_at FROM threads t
        WHERE t.archived=0 AND NOT EXISTS
        (SELECT 1 FROM thread_spawn_edges e WHERE e.child_thread_id=t.id)
        ORDER BY t.recency_at_ms DESC, t.updated_at DESC
        """
        var statement: OpaquePointer?
        let titledSQL = sql.replacingOccurrences(of: "t.updated_at FROM", with: "t.updated_at, t.name FROM")
        let hasTitles = sb_sqlite3_prepare_v2(db, titledSQL, -1, &statement, nil) == SQLITE_OK
        if !hasTitles {
            // Optional display metadata must not break counts on older schemas.
            sb_sqlite3_finalize(statement); statement = nil
            guard sb_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreFailure(db, path: path) }
        }
        defer { sb_sqlite3_finalize(statement) }
        var ids: [String] = [], unassigned = 0
        var activity: [String: Inventory.Activity] = [:]
        var titles: [String: String] = [:]
        while true {
            let result = sb_sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw StoreFailure(db, operation: .step, path: path) }
            func value(_ column: Int32) -> String? {
                sb_sqlite3_column_text(statement, column).map { String(cString: $0) }
            }
            guard sb_sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                  sb_sqlite3_column_type(statement, 2) == SQLITE_TEXT,
                  let id = value(0), UUID(uuidString: id) != nil, let source = value(2), !source.isEmpty else {
                throw DesktopFailure.unsupported
            }
            guard [SQLITE_TEXT, SQLITE_NULL].contains(sb_sqlite3_column_type(statement, 1)) else { throw DesktopFailure.unsupported }
            if source.lowercased().contains("subagent") { continue }
            guard let creator = value(1), !creator.isEmpty else { unassigned += 1; continue }
            if creator == account {
                ids.append(id)
                activity[id] = .init(recency: sb_sqlite3_column_int64(statement, 3), updated: sb_sqlite3_column_int64(statement, 4))
                if hasTitles, sb_sqlite3_column_type(statement, 5) == SQLITE_TEXT { titles[id] = value(5) }
            }
        }
        return Inventory(ids: ids, activity: activity, total: ids.count, unassigned: unassigned, titles: titles)
    }
}

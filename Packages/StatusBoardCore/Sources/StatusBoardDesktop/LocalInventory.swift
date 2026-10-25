import Foundation
import StatusBoardSQLite

enum DesktopFailure: Error { case unavailable, unsupported, unsafePath, timeout, identityChanged }

struct Inventory {
    struct Activity: Equatable { let recency: Int64; let updated: Int64 }
    let ids: [String]
    let activity: [String: Activity]
    let total: Int
    let unassigned: Int
}

struct LocalInventory {
    let path: String
    func read(account: String) throws -> Inventory {
        let connection = try ReadOnlyStore(path: path, busyTimeout: 200)
        defer { connection.close() }
        let db = connection.db
        // No prompts, names, rollout paths, or task bodies are selected.
        let sql = """
        SELECT t.id, t.creator_account_id, t.source, t.recency_at_ms, t.updated_at FROM threads t
        WHERE t.archived=0 AND NOT EXISTS
        (SELECT 1 FROM thread_spawn_edges e WHERE e.child_thread_id=t.id)
        ORDER BY t.recency_at_ms DESC, t.updated_at DESC
        """
        var statement: OpaquePointer?
        guard sb_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreFailure(db, path: path) }
        defer { sb_sqlite3_finalize(statement) }
        var ids: [String] = [], unassigned = 0
        var activity: [String: Inventory.Activity] = [:]
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
            }
        }
        return Inventory(ids: ids, activity: activity, total: ids.count, unassigned: unassigned)
    }
}

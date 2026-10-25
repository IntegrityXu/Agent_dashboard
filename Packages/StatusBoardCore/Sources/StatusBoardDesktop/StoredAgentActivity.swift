import Foundation
import StatusBoardSQLite
import StatusBoardCore

/// A resumed hosted subagent may have no desktop owner and emit only an
/// `interacted` event. Its recorded turn is usable for the inline list only
/// while its exact root_turn_id is independently confirmed processing by IPC.
/// This never contributes to task counts, audio, or top-level runtime recovery.
struct StoredAgentActivity {
    let path: String
    func read(roots: [String: DesktopObservation]) throws -> [String: [String: DesktopObservation]] {
        let active = roots.filter { LiveClassification.state($0.value) == .processing && $0.value.status == "inProgress" && $0.value.runID != nil }
        guard !active.isEmpty else { return [:] }
        let connection = try ReadOnlyStore(path: path, busyTimeout: 100)
        defer { connection.close() }
        let db = connection.db
        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sb_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw StoreFailure(db, path: path) }
            return statement
        }
        let turns = try prepare("""
            SELECT t.thread_id,t.turn_id,t.status FROM thread_turns t
            WHERE t.root_turn_id=? AND t.thread_id<>? AND t.rollout_ordinal=
              (SELECT MAX(n.rollout_ordinal) FROM thread_turns n WHERE n.thread_id=t.thread_id)
            """)
        defer { sb_sqlite3_finalize(turns) }
        let items = try prepare("""
            SELECT json_extract(item_json,'$.agentThreadId'),json_extract(item_json,'$.agentPath'),json_extract(item_json,'$.kind')
            FROM thread_items WHERE thread_id=? AND turn_id=? AND item_type='subAgentActivity' ORDER BY rollout_ordinal
            """)
        defer { sb_sqlite3_finalize(items) }
        let transient = unsafeBitCast(-1, to: sb_sqlite3_destructor_type.self)
        func bind(_ statement: OpaquePointer, _ values: [String]) throws {
            sb_sqlite3_reset(statement); sb_sqlite3_clear_bindings(statement)
            for (index, value) in values.enumerated() {
                guard sb_sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else { throw DesktopFailure.unavailable }
            }
        }
        func step(_ statement: OpaquePointer) throws -> Bool {
            let code = sb_sqlite3_step(statement)
            guard code == SQLITE_ROW || code == SQLITE_DONE else { throw StoreFailure(db, operation: .step, path: path) }
            return code == SQLITE_ROW
        }
        func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
            sb_sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var result: [String: [String: DesktopObservation]] = [:]
        for (root, observation) in active {
            guard let run = observation.runID else { continue }
            try bind(turns, [run, root])
            while try step(turns) {
                guard let thread = string(turns, 0), UUID(uuidString: thread) != nil,
                      let turn = string(turns, 1), let status = string(turns, 2) else { continue }
                try bind(items, [thread, turn])
                var activity: [WireValue] = []
                while try step(items) {
                    guard let id = string(items, 0), let path = string(items, 1), let kind = string(items, 2) else { continue }
                    activity.append(.object(["type": .string("subAgentActivity"), "agentThreadId": .string(id),
                        "agentPath": .string(path), "kind": .string(kind)]))
                }
                result[run, default: [:]][thread] = DesktopObservation(runID: turn, status: status, runtime: nil,
                    activeFlags: [], unread: nil, pendingRequestIDs: [], hasUnclassifiedRequests: false,
                    isHeartbeat: false, agents: AgentActivity.project(activity))
            }
        }
        return result
    }
}

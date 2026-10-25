import Foundation
import CryptoKit
import StatusBoardSQLite
import StatusBoardCore

/// Verified in builds 21477 (V6/xV) and 21828 (x8/bg): identity/local-host hashes and
/// readForStartup/open use this identity/host-scoped store, not legacyMigration.
struct DesktopReadScope: Equatable {
    let identityKey: String
    static let localHostKey = "local:" + digest(Data(#"["local","local",null]"#.utf8))

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func authenticated(_ response: [String: Any], account: String, now: Date = Date()) throws -> Self {
        guard let method = response["authMethod"] as? String, ["chatgpt", "chatgptAuthTokens"].contains(method),
              let token = response["authToken"] as? String else { throw DesktopFailure.unavailable }
        // Match the desktop's authenticated principal extraction. The helper
        // supplies the credential; retain only a hash, never log/store the token.
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw DesktopFailure.unsupported }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970,
              let auth = claims["https://api.openai.com/auth"] as? [String: Any],
              let id = (auth["chatgpt_account_id"] ?? auth["account_id"]) as? String, id == account,
              let user = (auth["user_id"] ?? auth["chatgpt_user_id"]) as? String, !user.isEmpty else {
            throw DesktopFailure.unavailable
        }
        let identity = try JSONSerialization.data(withJSONObject: ["chatgpt", id, user], options: [.withoutEscapingSlashes])
        return Self(identityKey: Self.digest(identity))
    }

    func unread(in state: [String: Any]) throws -> Set<String> {
        guard state["version"] as? Int == 1,
              let identities = state["unreadByIdentity"] as? [String: [String: [String]]] else {
            throw DesktopFailure.unsupported
        }
        // Missing identity/host means no stored unread in this exact scope.
        // Never adopt or union legacy, other-user, or remote-host entries.
        let ids = identities[identityKey]?[Self.localHostKey] ?? []
        guard ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw DesktopFailure.unsupported }
        return Set(ids)
    }
}

struct StoredCompletions {
    let path: String
    func read(candidates: Set<String>) throws -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        let connection = try ReadOnlyStore(path: path, busyTimeout: 200)
        defer { connection.close() }
        let db = connection.db
        // Read terminal status only. Never infer active/waiting from persisted
        // inProgress rows; those can outlive the process that produced them.
        let sql = "SELECT status, completed_at FROM thread_turns WHERE thread_id=? ORDER BY rollout_ordinal DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sb_sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw StoreFailure(db, path: path) }
        defer { sb_sqlite3_finalize(statement) }
        var result = Set<String>()
        let transient = unsafeBitCast(-1, to: sb_sqlite3_destructor_type.self)
        for id in candidates {
            sb_sqlite3_reset(statement); sb_sqlite3_clear_bindings(statement)
            guard sb_sqlite3_bind_text(statement, 1, id, -1, transient) == SQLITE_OK else { throw DesktopFailure.unavailable }
            let code = sb_sqlite3_step(statement)
            guard code == SQLITE_ROW || code == SQLITE_DONE else { throw StoreFailure(db, operation: .step, path: path) }
            if code == SQLITE_ROW, let text = sb_sqlite3_column_text(statement, 0), String(cString: text) == "completed",
               sb_sqlite3_column_type(statement, 1) != SQLITE_NULL { result.insert(id) }
        }
        return result
    }

    static func unloaded(_ completed: Set<String>, eligible: Set<String>, liveThreads: Set<String>) -> Set<String> {
        // A live stream with missing history or a revision gap is still live.
        // Missing observations must never resurrect an older completion.
        completed.intersection(eligible).subtracting(liveThreads)
    }
}

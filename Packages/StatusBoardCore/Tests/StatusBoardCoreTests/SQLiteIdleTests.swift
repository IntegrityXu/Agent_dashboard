import Foundation
import Testing
import SQLite3
import StatusBoardSQLite
@testable import StatusBoardCore
@testable import StatusBoardDesktop

/// Apple SQLite is deliberately the writer; production readers use the isolated
/// upstream runtime. Never touch the user's actual Codex databases in these tests.
private final class IdleWALFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var file: URL { root.appendingPathComponent("history.sqlite") }
    let id = UUID().uuidString, child = UUID().uuidString
    var writer: OpaquePointer?
    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try openWriter(create: true)
        try execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE threads(id TEXT,creator_account_id TEXT,source TEXT,archived INTEGER,recency_at_ms INTEGER,updated_at INTEGER);
            CREATE TABLE thread_spawn_edges(child_thread_id TEXT);
            CREATE TABLE thread_turns(thread_id TEXT,turn_id TEXT,root_turn_id TEXT,rollout_ordinal INTEGER,status TEXT,completed_at INTEGER);
            CREATE TABLE thread_items(thread_id TEXT,turn_id TEXT,item_type TEXT,item_json TEXT,rollout_ordinal INTEGER);
            INSERT INTO threads VALUES ('\(id)','account','cli',0,1,1);
            INSERT INTO thread_turns VALUES ('\(id)','root-run',NULL,1,'completed',1);
            INSERT INTO thread_turns VALUES ('\(child)','child-run','root-run',1,'inProgress',NULL);
            """)
    }
    func openWriter(create: Bool = false) throws {
        #expect(writer == nil)
        let flags = SQLite3.SQLITE_OPEN_READWRITE | (create ? SQLite3.SQLITE_OPEN_CREATE : 0)
        #expect(sqlite3_open_v2(file.path, &writer, flags, nil) == SQLite3.SQLITE_OK)
        _ = try #require(writer)
        var persist: Int32 = 0
        #expect(sqlite3_file_control(writer, "main", SQLite3.SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLite3.SQLITE_OK)
    }
    func execute(_ sql: String) throws {
        _ = try #require(writer)
        #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLite3.SQLITE_OK)
    }
    func closeWriter() {
        if let writer { #expect(sqlite3_close(writer) == SQLite3.SQLITE_OK) }
        writer = nil
    }
    func expectSidecarsAbsent() {
        #expect(!FileManager.default.fileExists(atPath: file.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: file.path + "-shm"))
    }
    deinit { closeWriter(); try? FileManager.default.removeItem(at: root) }
}

@Test func coldIdleWALReadsAllProductionStoresWithoutChangingMainDatabase() throws {
    let f = try IdleWALFixture()
    f.closeWriter(); f.expectSidecarsAbsent()
    let before = try Data(contentsOf: f.file)
    let attributes = try FileManager.default.attributesOfItem(atPath: f.file.path)
    #expect(ReadOnlyStore.sqliteVersion == "3.54.1")
    #expect(try StoredCompletions(path: f.file.path).read(candidates: [f.id]) == [f.id])
    #expect(try LocalInventory(path: f.file.path).read(account: "account").ids == [f.id])
    let root = DesktopObservation(runID: "root-run", status: "inProgress", runtime: "active", activeFlags: [],
        unread: false, pendingRequestIDs: [], hasUnclassifiedRequests: false, isHeartbeat: false)
    let agents = try StoredAgentActivity(path: f.file.path).read(roots: [f.id: root])
    #expect(agents["root-run"]?[f.child]?.status == "inProgress")
    #expect(try Data(contentsOf: f.file) == before)
    let after = try FileManager.default.attributesOfItem(atPath: f.file.path)
    #expect(attributes[.modificationDate] as? Date == after[.modificationDate] as? Date)
    #expect(attributes[.systemFileNumber] as? UInt64 == after[.systemFileNumber] as? UInt64)
}

@Test func repeatedAppleWriterIdleCyclesNeverRequireANewUserTurnToRead() throws {
    let f = try IdleWALFixture()
    let reader = StoredCompletions(path: f.file.path)
    for index in 0..<6 {
        if index > 0 { try f.openWriter() }
        let status = index.isMultiple(of: 2) ? "completed" : "inProgress"
        try f.execute("UPDATE thread_turns SET status='\(status)' WHERE thread_id='\(f.id)'")
        f.closeWriter(); f.expectSidecarsAbsent()
        let before = try Data(contentsOf: f.file)
        for _ in 0..<3 {
            #expect(try reader.read(candidates: [f.id]).contains(f.id) == index.isMultiple(of: 2))
        }
        #expect(try Data(contentsOf: f.file) == before)
    }
}

@Test func activeAppleWriterWALUpdatesRemainVisibleAndReadersReleaseLocks() throws {
    let f = try IdleWALFixture()
    f.closeWriter()
    let before = try Data(contentsOf: f.file)
    try f.openWriter()
    try f.execute("PRAGMA wal_autocheckpoint=0; INSERT INTO thread_turns VALUES ('\(f.id)','new-run',NULL,2,'inProgress',NULL)")
    #expect(try Data(contentsOf: f.file) == before) // Latest committed turn exists only in WAL.
    let reader = StoredCompletions(path: f.file.path)
    #expect(try reader.read(candidates: [f.id]).isEmpty)
    try f.execute("UPDATE thread_turns SET status='completed',completed_at=2 WHERE turn_id='new-run'")
    #expect(try reader.read(candidates: [f.id]) == [f.id])
    var log: Int32 = -1, checkpointed: Int32 = -1
    #expect(sqlite3_wal_checkpoint_v2(f.writer, nil, SQLite3.SQLITE_CHECKPOINT_TRUNCATE, &log, &checkpointed) == SQLite3.SQLITE_OK)
    #expect(log == 0 && checkpointed == 0)
    f.closeWriter(); f.expectSidecarsAbsent()
    #expect(try reader.read(candidates: [f.id]) == [f.id])
}

@Test func pinnedStoreConnectionRemainsReadOnlyAndMissingDatabaseIsNotCreated() throws {
    let f = try IdleWALFixture()
    f.closeWriter()
    let before = try Data(contentsOf: f.file)
    let reader = try ReadOnlyStore(path: f.file.path, busyTimeout: 50)
    #expect(sb_sqlite3_db_readonly(reader.db, "main") == 1)
    #expect(sb_sqlite3_exec(reader.db, "DELETE FROM thread_turns", nil, nil, nil) == SQLite3.SQLITE_READONLY)
    reader.close()
    #expect(try Data(contentsOf: f.file) == before)
    let missing = f.root.appendingPathComponent("missing.sqlite")
    do {
        _ = try ReadOnlyStore(path: missing.path, busyTimeout: 50)
        Issue.record("Missing read-only database unexpectedly opened")
    } catch let error as StoreFailure {
        #expect(error.code & 0xff == SQLite3.SQLITE_CANTOPEN)
        #expect(error.operation == .open)
        #expect(error.files?.database == false && error.files?.wal == false && error.files?.shm == false)
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}

@Test func storeFailureDiagnosticsExplainOperationAndSidecarsWithoutPathsOrSQL() throws {
    let f = try IdleWALFixture()
    f.closeWriter()
    let url = f.root.appendingPathComponent("diagnostics.jsonl")
    let log = DiagnosticLog(url: url)
    do { _ = try ReadOnlyStore(path: f.root.appendingPathComponent("private-name.sqlite").path, busyTimeout: 50) }
    catch { log.record(.completions, event: "read_failed_retrying", error: error) }
    let data = try Data(contentsOf: url)
    let row = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(row["sqliteOperation"] as? String == "open")
    #expect(row["systemErrno"] as? Int != nil)
    #expect((row["storeFiles"] as? [String: Bool])?["database"] == false)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains(f.root.path) && !text.contains("private-name") && !text.contains("SELECT"))
}

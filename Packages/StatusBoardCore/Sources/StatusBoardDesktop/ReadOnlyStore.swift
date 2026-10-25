import Foundation
import StatusBoardSQLite

/// All production stores use the pinned runtime and a real read-only connection.
/// Keep ordinary SQLite locking/WAL semantics; never bypass them with immutable or nolock.
final class ReadOnlyStore {
    static var sqliteVersion: String { String(cString: sb_sqlite3_libversion()) }
    private var handle: OpaquePointer?
    var db: OpaquePointer { handle! }

    init(path: String, busyTimeout: Int32) throws {
        let result = sb_sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK, handle != nil else {
            let failure = StoreFailure(handle, operation: .open, path: path, fallbackCode: result)
            close()
            throw failure
        }
        sb_sqlite3_busy_timeout(handle, busyTimeout)
    }
    func close() {
        if let handle { sb_sqlite3_close(handle) }
        handle = nil
    }
    deinit { close() }
}

/// Numeric errors and file-presence flags only: never capture SQL, paths or content.
struct StoreFailure: Error {
    enum Operation: String { case open, prepare, step }
    struct Files {
        let database: Bool
        let wal: Bool
        let shm: Bool
        init(path: String) {
            let manager = FileManager.default
            database = manager.fileExists(atPath: path)
            wal = manager.fileExists(atPath: path + "-wal")
            shm = manager.fileExists(atPath: path + "-shm")
        }
    }
    let code: Int32
    let systemErrno: Int32
    let operation: Operation
    let files: Files?
    init(_ db: OpaquePointer?, operation: Operation = .prepare, path: String? = nil, fallbackCode: Int32 = SQLITE_ERROR) {
        code = db.map { sb_sqlite3_extended_errcode($0) } ?? fallbackCode
        systemErrno = db.map { sb_sqlite3_system_errno($0) } ?? 0
        self.operation = operation
        files = path.map(Files.init)
    }
}

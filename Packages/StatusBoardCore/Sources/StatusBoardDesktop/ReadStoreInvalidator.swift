import Foundation
import CryptoKit
import Darwin

/// Watch both the directory (atomic replacement) and file (in-place write).
/// Also exposes the schema-validated read store for identity-scoped startup
/// recovery. Loaded streams still refresh their authoritative owner snapshot.
final class ReadStoreInvalidator {
    struct Snapshot {
        let state: [String: Any]
        let changed: Bool
    }
    let queue: Int32
    let directory: Int32
    let path: String
    var file: Int32 = -1
    var previous: Data?
    init(home: URL) throws {
        path = home.appendingPathComponent(".codex-global-state.json").path
        queue = kqueue()
        directory = Darwin.open(home.path, O_EVTONLY | O_NOFOLLOW)
        guard queue >= 0, directory >= 0 else {
            if queue >= 0 { Darwin.close(queue) }; if directory >= 0 { Darwin.close(directory) }
            throw DesktopFailure.unavailable
        }
        watch(directory); reopenFile()
    }
    deinit { if file >= 0 { Darwin.close(file) }; Darwin.close(directory); Darwin.close(queue) }
    func watch(_ fd: Int32) {
        var event = kevent(ident: UInt(fd), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
            fflags: UInt32(NOTE_WRITE | NOTE_DELETE | NOTE_RENAME), data: 0, udata: nil)
        _ = kevent(queue, &event, 1, nil, 0, nil)
    }
    func reopenFile() {
        if file >= 0 { Darwin.close(file) }
        file = Darwin.open(path, O_EVTONLY | O_NOFOLLOW)
        if file >= 0 { watch(file) }
    }
    func drain() -> Bool {
        var events = Array<Darwin.kevent>(repeating: Darwin.kevent(), count: 8)
        var noWait = timespec(tv_sec: 0, tv_nsec: 0)
        let count = kevent(queue, nil, 0, &events, Int32(events.count), &noWait)
        if count > 0 { reopenFile(); return true }
        return false
    }
    /// Compare and return the same read: invalidation and recovery cannot see
    /// different file versions, and each refresh parses the file only once.
    func read() throws -> Snapshot {
        let state = try readState()
        let next = Data(SHA256.hash(data: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])))
        defer { previous = next }
        return Snapshot(state: state, changed: previous != next)
    }
    private func readState() throws -> [String: Any] {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DesktopFailure.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= 16 * 1024 * 1024 else { throw DesktopFailure.unsafePath }
        let data = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 16 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-thread-read-state-v1"] as? [String: Any] else { throw DesktopFailure.unsupported }
        return state
    }
}


import Foundation
import Darwin
import StatusBoardCore

protocol DesktopTransport {
    var hasPendingBytes: Bool { get }
    var hasPartialFrame: Bool { get }
    func send(_ message: [String: Any]) throws
    func receive(timeout: Int32) throws -> [WireValue]
}

final class DesktopSocket: DesktopTransport {
    let fd: Int32
    var decoder = DesktopMetadataDecoder()
    init(home: URL) throws {
        let path = home.appendingPathComponent("ipc/ipc.sock").path
        for (item, type) in [(home.appendingPathComponent("ipc").path, S_IFDIR), (path, S_IFSOCK)] {
            var info = stat()
            guard lstat(item, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == type,
                  info.st_mode & 0o077 == 0 else { throw DesktopFailure.unsafePath }
        }
        let socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw DesktopFailure.unavailable }
        fd = socketFD
        var connected = false
        defer { if !connected { Darwin.close(socketFD) } }
        var noSignal: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var sendTimeout = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw DesktopFailure.unsafePath }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw DesktopFailure.unavailable }
        connected = true
    }
    deinit { Darwin.close(fd) }
    var hasPartialFrame: Bool { decoder.hasPartialFrame }
    var hasPendingBytes: Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, 0) > 0 && descriptor.revents & Int16(POLLIN) != 0
    }
    func send(_ message: [String: Any]) throws {
        let body = try JSONSerialization.data(withJSONObject: message)
        var length = UInt32(body.count).littleEndian
        var bytes = withUnsafeBytes(of: &length) { Data($0) }; bytes.append(body)
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                if sent < 0 && errno == EINTR { continue }
                guard sent > 0 else { throw DesktopFailure.unavailable }; offset += sent
            }
        }
    }

    func receive(timeout: Int32 = 100) throws -> [WireValue] {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, timeout)
        if ready < 0 && errno == EINTR { return [] }
        guard ready >= 0, descriptor.revents & Int16(POLLHUP | POLLERR | POLLNVAL) == 0 else { throw DesktopFailure.unavailable }
        guard descriptor.revents & Int16(POLLIN) != 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: 65536)
        let count = recv(fd, &bytes, bytes.count, 0)
        guard count > 0 else { throw DesktopFailure.unavailable }
        return try decoder.append(Data(bytes.prefix(count)))
    }
}

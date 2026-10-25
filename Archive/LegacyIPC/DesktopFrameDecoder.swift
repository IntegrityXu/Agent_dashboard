import Foundation

/// Splitting headers, splitting bodies, and multiple frames per read are all legal.
public struct DesktopFrameDecoder: Sendable {
    public static let limit = 8 * 1024 * 1024
    private var buffer = Data()
    public init() {}
    public mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let size = buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard size > 0 else { buffer.removeAll(); throw DesktopStreamError.malformed }
            guard size <= Self.limit else { buffer.removeAll(); throw DesktopStreamError.oversize }
            guard buffer.count >= 4 + size else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(size)))
            buffer.removeFirst(4 + size)
        }
        return frames
    }
}


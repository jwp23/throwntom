import Foundation

public enum SSEError: Error, Equatable {
    case frameTooLarge
}

/// Splits a text/event-stream byte stream into the data payload of each frame.
public struct SSEFrameSplitter {
    public static let maxFrameBytes = 1_048_576

    private var buffer = Data()

    /// Empty: all state starts at its declared default (empty buffer).
    public init() {}

    /// Feeds raw body bytes and returns the data payload of every frame completed so far.
    public mutating func feed(_ data: Data) throws -> [Data] {
        buffer += data
        var frames: [Data] = []
        while let end = frameEnd() {
            let frame = buffer[buffer.startIndex..<end.frameEnd]
            buffer = Data(buffer[end.nextStart...])
            if let payload = Self.payload(of: frame) {
                frames.append(payload)
            }
        }
        if buffer.count > Self.maxFrameBytes { throw SSEError.frameTooLarge }
        return frames
    }

    /// A frame ends at the first blank line; both "\n\n" and "\r\n\r\n" count.
    private func frameEnd() -> (frameEnd: Data.Index, nextStart: Data.Index)? {
        let lf = buffer.range(of: Data("\n\n".utf8))
        let crlf = buffer.range(of: Data("\r\n\r\n".utf8))
        switch (lf, crlf) {
        case let (l?, c?): return l.lowerBound <= c.lowerBound ? (l.lowerBound, l.upperBound) : (c.lowerBound, c.upperBound)
        case let (l?, nil): return (l.lowerBound, l.upperBound)
        case let (nil, c?): return (c.lowerBound, c.upperBound)
        case (nil, nil): return nil
        }
    }

    private static let dataPrefix = Data("data:".utf8)

    /// Byte-level line handling: in Swift "\r\n" is one Character, so String splitting on "\n" would miss CRLF lines.
    private static func payload(of frame: Data) -> Data? {
        var dataLines: [Data] = []
        for rawLine in frame.split(separator: 0x0A, omittingEmptySubsequences: false) {
            var line = rawLine
            if line.last == 0x0D { line = line.dropLast() }
            guard line.starts(with: dataPrefix) else { continue }
            var value = line.dropFirst(dataPrefix.count)
            if value.first == 0x20 { value = value.dropFirst() }
            dataLines.append(Data(value))
        }
        guard !dataLines.isEmpty else { return nil }
        return Data(dataLines.joined(separator: Data([0x0A])))
    }
}

import Foundation

public enum HTTPParseError: Error, Equatable {
    case headTooLarge
    case malformedStatusLine(String)
    case malformedChunkSize(String)
    case malformedChunkTerminator
}

public struct HTTPHead: Equatable, Sendable {
    public var status: Int
    /// Header names lowercased; duplicate names keep the last value.
    public var headers: [String: String]

    public var isChunked: Bool {
        headers["transfer-encoding"]?.lowercased().contains("chunked") ?? false
    }

    public var contentLength: Int? {
        headers["content-length"].flatMap(Int.init)
    }
}

/// Minimal HTTP/1.1 response parsing for a single trusted peer (Go net/http).
public enum HTTPParser {
    public static let maxHeadBytes = 65_536
    private static let headTerminator = Data("\r\n\r\n".utf8)

    /// Parses the status line and headers. Returns nil when the terminator has not arrived yet.
    public static func parseHead(_ data: Data) throws -> (head: HTTPHead, bodyStart: Int)? {
        guard let range = data.range(of: headTerminator) else {
            if data.count > maxHeadBytes { throw HTTPParseError.headTooLarge }
            return nil
        }
        if range.lowerBound - data.startIndex > maxHeadBytes { throw HTTPParseError.headTooLarge }
        let headText = String(decoding: data[data.startIndex..<range.lowerBound], as: UTF8.self)
        var lines = headText.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst()
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."), let status = Int(parts[1]) else {
            throw HTTPParseError.malformedStatusLine(statusLine)
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return (HTTPHead(status: status, headers: headers), range.upperBound - data.startIndex)
    }
}

/// Incremental decoder for Transfer-Encoding: chunked bodies.
public struct ChunkedDecoder {
    private enum Phase { case size, body(remaining: Int), bodyTerminator, finished }

    private var phase = Phase.size
    private var buffer = Data()
    private static let crlf = Data("\r\n".utf8)
    private static let maxSizeLineBytes = 64
    public static let maxChunkBytes = 1_048_576

    public private(set) var isFinished = false

    /// Empty: all state starts at its declared default (phase .size, empty buffer).
    public init() {}

    /// Feeds raw bytes and returns whatever decoded body bytes became available.
    public mutating func feed(_ data: Data) throws -> Data {
        buffer += data
        var out = Data()
        while true {
            switch phase {
            case .size:
                guard let range = buffer.range(of: Self.crlf) else {
                    if buffer.count > Self.maxSizeLineBytes {
                        throw HTTPParseError.malformedChunkSize(String(decoding: buffer, as: UTF8.self))
                    }
                    return out
                }
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                let sizeText = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
                    throw HTTPParseError.malformedChunkSize(line)
                }
                guard size >= 0, size <= Self.maxChunkBytes else {
                    throw HTTPParseError.malformedChunkSize(line)
                }
                buffer = Data(buffer[range.upperBound...])
                phase = size == 0 ? .finished : .body(remaining: size)
            case .body(let remaining):
                if buffer.isEmpty { return out }
                let take = min(remaining, buffer.count)
                out += buffer.prefix(take)
                buffer = Data(buffer.dropFirst(take))
                phase = remaining == take ? .bodyTerminator : .body(remaining: remaining - take)
            case .bodyTerminator:
                guard buffer.count >= 2 else { return out }
                guard buffer.prefix(2) == Self.crlf else { throw HTTPParseError.malformedChunkTerminator }
                buffer = Data(buffer.dropFirst(2))
                phase = .size
            case .finished:
                isFinished = true
                return out
            }
        }
    }
}

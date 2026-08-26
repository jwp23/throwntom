import Foundation

/// HTTP/1.1 over the daemon's Unix socket: one connection per request, one long-lived connection per event stream.
public final class UnixSocketTransport: DaemonTransport {
    public let socketPath: String

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    public func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
        let connection = SocketConnection(path: socketPath)
        defer { connection.close() }
        try await connection.open()
        try await connection.send(Self.requestBytes(method: method, path: path, body: body, streaming: false))
        var raw = Data()
        while let chunk = try await connection.receive() {
            raw += chunk
        }
        guard let parsed = try HTTPParser.parseHead(raw) else {
            throw DaemonError.malformedResponse("response ended before headers completed")
        }
        var responseBody = Data(raw.dropFirst(parsed.bodyStart))
        if parsed.head.isChunked {
            var decoder = ChunkedDecoder()
            responseBody = try decoder.feed(responseBody)
        } else if let length = parsed.head.contentLength {
            responseBody = responseBody.prefix(length)
        }
        return HTTPResponse(status: parsed.head.status, headers: parsed.head.headers, body: responseBody)
    }

    public func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let connection = SocketConnection(path: socketPath)
            let reader = Task {
                do {
                    try await connection.open()
                    try await connection.send(Self.requestBytes(method: "GET", path: path, body: nil, streaming: true))
                    try await Self.pumpFrames(from: connection, into: continuation)
                    continuation.finish(throwing: DaemonError.transport("event stream closed"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                connection.close()
            }
        }
    }

    private static func pumpFrames(from connection: SocketConnection,
                                   into continuation: AsyncThrowingStream<Data, Error>.Continuation) async throws {
        var pending = Data()
        var head: HTTPHead?
        var chunked: ChunkedDecoder?
        var splitter = SSEFrameSplitter()
        while let chunk = try await connection.receive() {
            var bodyBytes: Data
            if head == nil {
                pending += chunk
                guard let parsed = try HTTPParser.parseHead(pending) else { continue }
                guard parsed.head.status == 200 else {
                    let message = String(decoding: pending.dropFirst(parsed.bodyStart), as: UTF8.self)
                    throw DaemonError.http(status: parsed.head.status, message: message)
                }
                head = parsed.head
                if parsed.head.isChunked { chunked = ChunkedDecoder() }
                bodyBytes = Data(pending.dropFirst(parsed.bodyStart))
                pending = Data()
            } else {
                bodyBytes = chunk
            }
            if var decoder = chunked {
                bodyBytes = try decoder.feed(bodyBytes)
                chunked = decoder
            }
            for frame in try splitter.feed(bodyBytes) {
                continuation.yield(frame)
            }
        }
    }

    static func requestBytes(method: String, path: String, body: Data?, streaming: Bool) -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: throwntomd\r\nConnection: close\r\n"
        head += streaming ? "Accept: text/event-stream\r\n" : "Accept: application/json\r\n"
        if let body {
            head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + (body ?? Data())
    }
}

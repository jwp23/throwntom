import Foundation

// MARK: - UnixSocketTransport

/// HTTP/1.1 over the daemon's Unix socket: one connection per request, one long-lived connection per event stream.
public final class UnixSocketTransport: DaemonTransport {

  // MARK: Lifecycle

  public init(socketPath: String, requestTimeout: Duration = UnixSocketTransport.defaultRequestTimeout) {
    self.socketPath = socketPath
    self.requestTimeout = requestTimeout
  }

  // MARK: Public

  /// How long a single request may take before its connection is closed and the call fails.
  public static let defaultRequestTimeout = Duration.seconds(5)

  public let socketPath: String

  /// Races the exchange against the deadline; whichever finishes first decides the outcome, and the
  /// loser is cancelled. A stalled daemon therefore fails the call instead of parking it forever.
  /// The deadline only throws: cancelling the group is what closes the connection, so the timeout
  /// cannot lose the race to the socket error its own close would raise.
  public func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
    let connection = SocketConnection(path: socketPath)
    defer { connection.close() }
    let bytes = Self.requestBytes(method: method, path: path, body: body, streaming: false)
    let timeout = requestTimeout
    return try await withThrowingTaskGroup(of: HTTPResponse.self) { group in
      group.addTask { try await Self.exchange(bytes, over: connection) }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw DaemonError.timedOut(after: timeout)
      }
      defer { group.cancelAll() }
      guard let response = try await group.next() else {
        throw DaemonError.transport("request ended without a response")
      }
      return response
    }
  }

  public func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      let connection = SocketConnection(path: socketPath)
      // Installed before the reader starts so a consumer that drops the stream immediately
      // still tears the connection down.
      let reader = PendingTask()
      continuation.onTermination = { _ in
        reader.cancel()
        connection.close()
      }
      reader.hold(Task {
        do {
          try await connection.open()
          try await connection.send(Self.requestBytes(method: "GET", path: path, body: nil, streaming: true))
          try await Self.pumpFrames(from: connection, into: continuation)
          continuation.finish(throwing: DaemonError.transport("event stream closed"))
        } catch {
          continuation.finish(throwing: error)
        }
      })
    }
  }

  // MARK: Internal

  static func requestBytes(method: String, path: String, body: Data?, streaming: Bool) -> Data {
    var head = "\(method) \(path) HTTP/1.1\r\nHost: throwntomd\r\nConnection: close\r\n"
    head += streaming ? "Accept: text/event-stream\r\n" : "Accept: application/json\r\n"
    if let body {
      head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n"
    }
    head += "\r\n"
    return Data(head.utf8) + (body ?? Data())
  }

  // MARK: Private

  private let requestTimeout: Duration

  private static func exchange(_ bytes: Data, over connection: SocketConnection) async throws -> HTTPResponse {
    try await connection.open()
    try await connection.send(bytes)
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

  private static func pumpFrames(
    from connection: SocketConnection,
    into continuation: AsyncThrowingStream<Data, Error>.Continuation,
  ) async throws {
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
        if parsed.head.isChunked {
          chunked = ChunkedDecoder()
        }
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

}

// MARK: - PendingTask

/// A cancellation handle that can be handed out before the task it refers to exists.
/// A cancel that lands first is applied as soon as the task arrives.
private final class PendingTask: @unchecked Sendable {

  // MARK: Internal

  func hold(_ task: Task<Void, Never>) {
    lock.lock()
    let wasCancelled = isCancelled
    self.task = task
    lock.unlock()
    if wasCancelled {
      task.cancel()
    }
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    let task = task
    lock.unlock()
    task?.cancel()
  }

  // MARK: Private

  private let lock = NSLock()
  private var task: Task<Void, Never>?
  private var isCancelled = false

}

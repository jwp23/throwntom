import XCTest
@testable import ThrowntomClient

// MARK: - EventStreamTests

/// What `events` asks the daemon for, what it makes of the bytes that come back, and what it
/// leaves behind when the consumer walks away. A real daemon sends a well-formed stream in
/// whatever pieces it likes; these tests choose the pieces.
final class EventStreamTests: XCTestCase {

  // MARK: Internal

  override func setUpWithError() throws {
    server = try ScriptedSocketServer()
    transport = UnixSocketTransport(socketPath: try XCTUnwrap(server).path)
  }

  override func tearDown() {
    server?.stop()
    server = nil
  }

  func testTheStreamAsksTheDaemonForEvents() throws {
    let server = try XCTUnwrap(server)
    let log = EventLog()
    let consumer = log.consume(transport.events("/v1/events"))
    defer { consumer.cancel() }

    let head = try server.requestHead()

    XCTAssertEqual(head.components(separatedBy: "\r\n"), [
      "GET /v1/events HTTP/1.1",
      "Host: throwntomd",
      "Connection: close",
      "Accept: text/event-stream",
    ])
  }

  func testFramesArriveAsTheDaemonWritesThem() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }

    try server.reply(Self.streamHead + "data: one\n\n")
    try await waitUntil("the first frame") { log.frames.count >= 1 }
    try server.reply("data: two\n\n")
    try await waitUntil("the second frame") { log.frames.count >= 2 }

    XCTAssertEqual(log.frames.map { String(decoding: $0, as: UTF8.self) }, ["one", "two"])
  }

  /// The head arrives in as many reads as the daemon's writes take; only the bytes after it are
  /// the stream's own.
  func testAHeadSplitAcrossWritesStillDeliversTheFirstFrame() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }

    try server.reply("HTTP/1.1 200 OK\r\nContent-Ty")
    try await Task.sleep(for: .milliseconds(100))
    try server.reply("pe: text/event-stream\r\n\r\ndata: one\n\n")

    try await waitUntil("the first frame") { log.frames.count >= 1 }
    XCTAssertEqual(log.frames.map { String(decoding: $0, as: UTF8.self) }, ["one"])
  }

  /// A stream the daemon refuses is reported as the refusal it is, in the daemon's own words,
  /// rather than as bytes that failed to parse as frames.
  func testARefusedStreamFailsWithTheDaemonsOwnStatus() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }

    try server.reply("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 8\r\n\r\nnot yet.")

    try await waitUntil("the stream to fail") { log.error != nil }
    XCTAssertEqual(log.error as? DaemonError, .http(status: 503, message: "not yet."))
    XCTAssertEqual(log.frames.count, 0)
  }

  /// A chunked stream is decoded before it is split into frames: chunk boundaries are the
  /// daemon's business and fall wherever they like, including mid-frame.
  func testAChunkedStreamIsDecodedBeforeItIsSplitIntoFrames() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }

    try server.reply("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
    try server.reply(Self.chunk("data: on") + Self.chunk("e\n\n"))

    try await waitUntil("the first frame") { log.frames.count >= 1 }
    XCTAssertEqual(log.frames.map { String(decoding: $0, as: UTF8.self) }, ["one"])
  }

  /// A daemon that closes the stream has stopped answering, which is a failure for the consumer
  /// and not the orderly end of a sequence it asked for.
  func testTheStreamFailsWhenTheDaemonEndsIt() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }
    try server.reply(Self.streamHead + "data: one\n\n")
    try await waitUntil("the first frame") { log.frames.count >= 1 }

    try server.endReply()

    try await waitUntil("the stream to fail") { log.error != nil }
    XCTAssertEqual(log.error as? DaemonError, .transport("event stream closed"))
  }

  /// A stream that ends by itself takes the socket with it too. Nothing is left to cancel here —
  /// the reader has already run out of stream — so hanging up is the connection's own business.
  func testTheClientHangsUpWhenTheDaemonEndsTheStream() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    defer { consumer.cancel() }
    try server.reply(Self.streamHead + "data: one\n\n")
    try await waitUntil("the first frame") { log.frames.count >= 1 }

    try server.endReply()

    try await waitUntil("the client to hang up") { server.closedByClient >= 1 }
  }

  /// A consumer that drops the stream takes the socket with it; nothing is left reading a
  /// connection whose frames have nowhere to go.
  func testDroppingTheStreamHangsUpOnTheDaemon() async throws {
    let server = try XCTUnwrap(server)
    let (log, consumer) = try startedStream()
    try server.reply(Self.streamHead + "data: one\n\n")
    try await waitUntil("the first frame") { log.frames.count >= 1 }

    consumer.cancel()

    try await waitUntil("the client to hang up") { server.closedByClient >= 1 }
  }

  /// A stream that cannot be opened at all fails its consumer rather than staying silent.
  func testAStreamThatCannotConnectFailsItsConsumer() async throws {
    let missing = UnixSocketTransport(socketPath: "/tmp/tt-missing-\(UUID().uuidString.prefix(8)).sock")
    let log = EventLog()
    let consumer = log.consume(missing.events("/v1/events"))
    defer { consumer.cancel() }

    try await waitUntil("the stream to fail") { log.error != nil }
    guard case .transport = log.error as? DaemonError else {
      return XCTFail("unexpected \(String(describing: log.error))")
    }
  }

  // MARK: Private

  private static let streamHead = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n"

  private var server: ScriptedSocketServer?
  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var transport: UnixSocketTransport!

  private static func chunk(_ text: String) -> String {
    String(text.utf8.count, radix: 16) + "\r\n" + text + "\r\n"
  }

  /// Starts a stream, consumes it on a task of its own, and returns once the daemon has the
  /// request — which is where a test that scripts the answer has to begin.
  private func startedStream() throws -> (log: EventLog, consumer: Task<Void, Never>) {
    let log = EventLog()
    let consumer = log.consume(try XCTUnwrap(transport).events("/v1/events"))
    _ = try XCTUnwrap(server).requestHead()
    return (log, consumer)
  }

}

// MARK: - EventLog

/// Thread-safe record of the frames a stream yielded and how it ended, readable from the test's
/// actor while a task of its own consumes the stream.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
private final class EventLog: @unchecked Sendable {

  // MARK: Internal

  var frames: [Data] {
    lock.withLock { _frames }
  }

  var error: Error? {
    lock.withLock { _error }
  }

  /// Consumes the stream until it ends; returns immediately.
  func consume(_ stream: AsyncThrowingStream<Data, Error>) -> Task<Void, Never> {
    Task {
      do {
        for try await frame in stream {
          lock.withLock { _frames.append(frame) }
        }
      } catch {
        lock.withLock { _error = error }
      }
    }
  }

  // MARK: Private

  private let lock = NSLock()
  private var _frames = [Data]()
  private var _error: Error?

}

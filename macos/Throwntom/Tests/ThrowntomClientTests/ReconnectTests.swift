import XCTest
@testable import ThrowntomClient

// MARK: - OutageTransport

/// An event stream that stays broken until `recover()` is called, then serves one idle frame
/// and holds the stream open. Stands in for a daemon that launchd has not started yet.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class OutageTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  var dials: Int {
    lock.withLock { _dials }
  }

  func recover() {
    lock.withLock { _isReachable = true }
  }

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    guard lock.withLock({ _isReachable }) else {
      throw Self.outage
    }
    return HTTPResponse(status: 200, headers: [:], body: Data(#"{"active":[],"done":[]}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    let reachable = lock.withLock {
      _dials += 1
      return _isReachable
    }
    return AsyncThrowingStream { continuation in
      guard reachable else {
        continuation.finish(throwing: Self.outage)
        return
      }
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
    }
  }

  // MARK: Private

  /// The verbatim text a missing Unix socket produces, which is what used to reach the window.
  private static let outage = DaemonError.transport("POSIXErrorCode(rawValue: 2): No such file or directory")

  private let lock = NSLock()
  private var _dials = 0
  private var _isReachable = false

}

// MARK: - RecoveringRegistrar

/// Stands in for launchd: registering the agent is what makes the daemon reachable.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class RecoveringRegistrar: LaunchAgentRegistrar, @unchecked Sendable {

  // MARK: Lifecycle

  init(starts transport: OutageTransport) {
    self.transport = transport
  }

  // MARK: Internal

  func ensureAgentRegistered() throws {
    transport.recover()
  }

  // MARK: Private

  private let transport: OutageTransport

}

// MARK: - RefusingRegistrar

/// A registrar that cannot register, so the client's request to launchd goes nowhere.
struct RefusingRegistrar: LaunchAgentRegistrar {
  struct Denied: Error { }

  func ensureAgentRegistered() throws {
    throw Denied()
  }
}

// MARK: - GarbledTransport

/// A daemon that answers, but with a body the client cannot decode.
struct GarbledTransport: DaemonTransport {
  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data("not json at all".utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish(throwing: DaemonError.transport("no event stream")) }
  }
}

// MARK: - ReconnectTests

@MainActor
final class ReconnectTests: XCTestCase {

  // MARK: Internal

  /// Registering the agent is what ends the outage, so the dial after it must come from the
  /// short end of the backoff. Before this, the client asked launchd to start the daemon and
  /// then waited out the escalated delay, paying for its own fix in multi-second steps.
  func testRetriesQuicklyOnceTheAgentHasBeenRegistered() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(
      transport: transport,
      registrar: RecoveringRegistrar(starts: transport),
      backoff: Self.slowAfterRegistering,
    )
    client.start()
    defer { client.stop() }

    try await waitUntil(timeout: 2) { client.connection == .connected }
    XCTAssertEqual(transport.dials, DaemonClient.failuresBeforeRegistering + 1)
  }

  /// The window shows this text under the chips, so it has to read as a sentence rather than
  /// as the transport's own description of a missing socket.
  func testAnOutageReadsAsASentenceNotATransportError() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar(), backoff: [.milliseconds(10)])
    client.start()
    defer { client.stop() }

    try await waitUntil { client.unresolvedError != nil }
    XCTAssertEqual(client.unresolvedError, "Timer is restarting…")
  }

  /// A registration that fails is the one error most likely to be framework noise, so it needs
  /// the same treatment as every other error the window shows.
  func testAFailedRegistrationDoesNotShowTheFrameworkError() async throws {
    let client = DaemonClient(
      transport: OutageTransport(),
      registrar: RefusingRegistrar(),
      backoff: Self.slowAfterRegistering,
    )
    client.start()
    defer { client.stop() }

    try await waitUntil { client.connection == .startingDaemon }
    try await waitUntil { client.unresolvedError != nil }

    XCTAssertEqual(client.unresolvedError, "The timer could not be started.")
  }

  /// The daemon answered, so telling the reader it could not be reached would send them after
  /// a connection problem that does not exist.
  func testAnUnreadableReplyIsNotReportedAsAnUnreachableTimer() async throws {
    let client = DaemonClient(transport: GarbledTransport(), registrar: RecordingRegistrar())
    defer { client.stop() }

    do {
      _ = try await client.command("task add hello")
      XCTFail("an undecodable reply must throw")
    } catch {
      XCTAssertEqual(client.unresolvedError, "The timer sent a reply we could not read.")
    }
  }

  /// Rewinding the backoff is justified by launchd having been asked to start the daemon. When
  /// the ask failed, nothing was fixed, so the outage keeps escalating instead.
  func testAFailedRegistrationDoesNotRewindTheBackoff() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(transport: transport, registrar: RefusingRegistrar(), backoff: Self.slowAfterRegistering)
    client.start()
    defer { client.stop() }

    try await waitUntil { transport.dials >= DaemonClient.failuresBeforeRegistering }
    try await Task.sleep(for: .milliseconds(200))

    XCTAssertEqual(client.connection, .startingDaemon, "the reconnect loop is still running, just waiting")
    XCTAssertEqual(
      transport.dials,
      DaemonClient.failuresBeforeRegistering,
      "a rewound backoff would have dialled again 10 ms later",
    )
  }

  // MARK: Private

  /// Short until the registration attempt, then long enough that a client which does not rewind
  /// the backoff never reaches the next dial inside the test's timeout.
  private static let slowAfterRegistering: [Duration] = [
    .milliseconds(10),
    .milliseconds(10),
    .seconds(30),
  ]

}

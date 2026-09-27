import XCTest
@testable import ThrowntomClient

// MARK: - DialCountingTransport

/// Counts event-stream dials on the way through to a real transport, so a test can wait for the
/// reconnect loop to have actually run rather than for a stretch of wall clock that a loaded
/// machine may spend doing nothing.
// `_dials` is only touched under `lock`; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class DialCountingTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Lifecycle

  init(_ wrapped: DaemonTransport) {
    self.wrapped = wrapped
  }

  // MARK: Internal

  var dials: Int {
    lock.withLock { _dials }
  }

  func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
    try await wrapped.request(method, path, body: body)
  }

  func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
    lock.withLock { _dials += 1 }
    return wrapped.events(path)
  }

  // MARK: Private

  private let wrapped: DaemonTransport
  private let lock = NSLock()
  private var _dials = 0

}

// MARK: - DaemonClientTests

@MainActor
final class DaemonClientTests: XCTestCase {

  // MARK: Internal

  @MainActor
  override func setUp() async throws {
    daemon = try DaemonHarness()
    try await daemon.start()
    registrar = RecordingRegistrar()
  }

  @MainActor
  override func tearDown() async throws {
    daemon.cleanup()
  }

  func testPublishesStateAndTasksFromDaemon() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    XCTAssertEqual(client.state?.state, .idle)
    XCTAssertEqual(client.tasks, TaskList())

    let message = try await client.command("task add hello")
    XCTAssertFalse(message.isEmpty)
    try await waitUntil("the added task to reach the window") { client.tasks.active.map(\.description) == ["hello"] }
  }

  func testTimerVerbRefusedSurfacesAs409() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    do {
      try await client.timer(.pause)
      XCTFail("pause while idle must be refused")
    } catch DaemonError.http(let status, _) {
      XCTAssertEqual(status, 409)
    }
  }

  func testUnknownCommandSurfacesAs400WithMessage() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    do {
      _ = try await client.command("bogus")
      XCTFail("expected an error")
    } catch let error as DaemonError {
      XCTAssertEqual(error, .http(status: 400, message: "unknown command: bogus"))
    }
  }

  func testReconnectsAfterDaemonRestart() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    daemon.stop()
    try await waitUntil("the connection to drop") { client.connection != .connected }
    try await daemon.start()
    try await waitUntil("the client to reconnect", timeout: 5) { client.connection == .connected }
    XCTAssertEqual(client.state?.state, .idle)
  }

  func testRefusedCommandSurfacesInUnresolvedErrorWhileConnected() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    do {
      try await client.timer(.pause)
      XCTFail("pause while idle must be refused")
    } catch DaemonError.http(let status, _) {
      XCTAssertEqual(status, 409)
    }
    XCTAssertEqual(
      client.unresolvedError,
      "nothing to pause: timer is not running",
      "the daemon's own words reach the window",
    )
  }

  func testTransportOutageAfterRefusedCommandSurfacesTheOutageNotTheStaleRefusal() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    do {
      try await client.timer(.pause)
      XCTFail("pause while idle must be refused")
    } catch DaemonError.http(let status, _) {
      XCTAssertEqual(status, 409)
    }
    XCTAssertNotNil(client.unresolvedError, "the refusal should be visible on its own")

    daemon.stop()
    try await waitUntil("the connection to drop") { client.connection != .connected }
    try await waitUntil("the outage to replace the stale refusal") { client.unresolvedError == client.lastError }
  }

  func testConnectedClientHasNoErrorToShow() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    XCTAssertNil(client.unresolvedError)
  }

  func testOutageReasonStaysVisibleUntilReconnect() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    daemon.stop()
    try await waitUntil("an error the window can show") { client.unresolvedError != nil }
    XCTAssertEqual(client.unresolvedError, client.lastError)

    try await daemon.start()
    try await waitUntil("the reconnect to clear the error", timeout: 5) { client.unresolvedError == nil }
    XCTAssertNotNil(client.lastError, "the error is only hidden, not forgotten")
  }

  /// Over a real socket that never appears: launchd is asked once and then left to its own
  /// KeepAlive. Asking again would unregister the job first, killing a daemon that had just
  /// started, so the client keeps reporting the outage instead of repeating the ask.
  func testRegistersTheAgentOnceAndKeepsReportingThePersistentOutage() async throws {
    let missing = UnixSocketTransport(socketPath: daemon.home.appendingPathComponent("nope.sock").path)
    let transport = DialCountingTransport(missing)
    let client = DaemonClient(transport: transport, registrar: registrar, backoff: [.milliseconds(30)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the registration that ends the outage") { self.registrar.registrations >= 1 }
    XCTAssertEqual(client.connection, .startingDaemon)

    // Waiting on dials rather than on wall clock: a loaded machine that managed only a couple of
    // reconnects in a fixed sleep would pass this test with the repeat registration still in.
    try await waitUntil("dials well past where repeat registrations would fall") {
      transport.dials >= DaemonClient.failuresBeforeRegistering * 3 + 1
    }

    XCTAssertEqual(registrar.registrations, 1, "further failures must not ask launchd again")
    XCTAssertEqual(client.connection, .startingDaemon)
  }

  func testStatsReadsTheDashboardFromARealDaemon() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    let stats = try await client.stats()
    XCTAssertEqual(stats.today.pomodoros, 0)
    XCTAssertEqual(stats.allTime, stats.today, "a fresh daemon has one empty period everywhere")
    XCTAssertEqual(stats.streaks, .init(current: 0, longest: 0))
  }

  /// A fresh client's recorded intent is `.running`, so `start()` must actually dial: it is the
  /// guard on `intent` and `streamTask` together that decide whether the reconnect loop ever
  /// begins, and a guard broken either way leaves the stream permanently undialled.
  func testStartDialsTheEventStreamWhenIntentIsRunning() async throws {
    let missing = UnixSocketTransport(socketPath: daemon.home.appendingPathComponent("nope.sock").path)
    let transport = DialCountingTransport(missing)
    let client = DaemonClient(transport: transport, registrar: registrar, backoff: [.milliseconds(30)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the event stream to be dialled") { transport.dials >= 1 }
  }

  /// The frame loop's own cancellation guard: a decoded frame must still reach `connection` and
  /// `state` when the enclosing task has not been cancelled.
  func testConnectsAfterReceivingTheFirstFrame() async throws {
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    defer { client.stop() }
    try await waitUntil("the client to connect") { client.connection == .connected }
  }

  /// `startStalled` is what tells `.reaching` from `.notAnswering` on the screen, and the two
  /// must part ways exactly at the third failure past registration, not the fourth.
  func testServiceReportsNotAnsweringAfterThreeFailuresPastRegistration() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(
      transport: transport,
      registrar: registrar,
      backoff: [.milliseconds(1), .milliseconds(1), .milliseconds(1), .seconds(30)],
    )
    client.start()
    defer { client.stop() }
    try await waitUntil("the third failure past registration to report not answering") {
      client.serviceStatus == .notAnswering
    }
  }

  /// A stop is a fresh footing, not a stall the next Start inherits: `startStalled` from the
  /// outage being left behind must not survive into the stopped state.
  func testStoppingTheServiceClearsANotAnsweringStall() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(transport: transport, registrar: registrar, backoff: [.milliseconds(1)])
    client.start()
    try await waitUntil("the service to report not answering") { client.serviceStatus == .notAnswering }

    await client.stopService()

    XCTAssertFalse(client.startStalled, "stopping the service clears a stall from the outage it is leaving")
  }

  // MARK: Private

  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var daemon: DaemonHarness!
  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var registrar: RecordingRegistrar!

  private func connectedClient() async throws -> DaemonClient {
    let client = DaemonClient(transport: UnixSocketTransport(socketPath: daemon.socketPath), registrar: registrar)
    client.start()
    try await waitUntil("the client to connect") { client.connection == .connected }
    return client
  }

}

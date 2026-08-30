import XCTest
@testable import ThrowntomClient

// MARK: - RecordingRegistrar

// `_calls` is only touched under `lock`; LaunchAgentRegistrar requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class RecordingRegistrar: LaunchAgentRegistrar, @unchecked Sendable {

  // MARK: Internal

  var calls: Int {
    lock.withLock { _calls }
  }

  func ensureAgentRegistered() throws {
    lock.withLock { _calls += 1 }
  }

  // MARK: Private

  private let lock = NSLock()
  private var _calls = 0

}

// MARK: - DaemonClientTests

@MainActor
final class DaemonClientTests: XCTestCase {

  // MARK: Internal

  override func setUp() async throws {
    daemon = try DaemonHarness()
    try await daemon.start()
    registrar = RecordingRegistrar()
  }

  override func tearDown() {
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
    try await waitUntil("the client to reconnect", timeout: 10) { client.connection == .connected }
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
    try await waitUntil("the reconnect to clear the error", timeout: 10) { client.unresolvedError == nil }
    XCTAssertNotNil(client.lastError, "the error is only hidden, not forgotten")
  }

  /// Over a real socket that never appears: launchd is asked once and then left to its own
  /// KeepAlive. Asking again would unregister the job first, killing a daemon that had just
  /// started, so the client keeps reporting the outage instead of repeating the ask.
  func testRegistersTheAgentOnceAndKeepsReportingThePersistentOutage() async throws {
    let missing = UnixSocketTransport(socketPath: daemon.home.appendingPathComponent("nope.sock").path)
    let client = DaemonClient(transport: missing, registrar: registrar, backoff: [.milliseconds(30)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the registration that ends the outage") { self.registrar.calls >= 1 }
    XCTAssertEqual(client.connection, .startingDaemon)

    try await Task.sleep(for: .milliseconds(500))

    XCTAssertEqual(registrar.calls, 1, "further failures must not ask launchd again")
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

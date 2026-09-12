import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - ServiceRegistrationIsolationTests

/// throwntom-339. The client is `@MainActor`, so anything it calls without awaiting runs where the
/// window is drawn. Driving launchd is `Process` and `waitUntilExit`, up to four of them for one
/// registration, which is a frozen window for as long as launchd takes.
@MainActor
final class ServiceRegistrationIsolationTests: XCTestCase {

  func testPressingStartDoesNotDriveLaunchdOnTheMainActor() async {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)

    await client.startService()
    defer { client.stop() }

    XCTAssertEqual(registrar.calls, [.register])
    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

  func testPressingStopDoesNotDriveLaunchdOnTheMainActor() async {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)

    await client.stopService()

    XCTAssertEqual(registrar.calls, [.stop])
    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

  /// The site the bug was found at: the reconnect loop asks launchd for the daemon after three
  /// failed dials, and it does that from the same main actor the window is drawn on.
  func testTheReconnectLoopDoesNotDriveLaunchdOnTheMainActor() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: OutageTransport(), registrar: registrar, backoff: [.milliseconds(5)])
    client.start()
    defer { client.stop() }

    try await waitUntil("the loop to ask launchd for the daemon") { registrar.registrations == 1 }

    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

}

// MARK: - ServiceVerbSerialisationTests

/// Start and Stop each contact launchd and then write the connection state that follows from what
/// launchd did. Nothing may get between those two halves. While the launchd calls blocked the main
/// actor nothing could, so the ordering came for nothing; awaiting them is what lets a second
/// press in, and the ordering now has to be kept on purpose.
@MainActor
final class ServiceVerbSerialisationTests: XCTestCase {

  /// The interleaving that reaches ADR-010: the Stop finishes last, so it writes the stopped
  /// ending over a stream the Start opened while it was waiting on launchd. The service the user
  /// stopped goes on dialling, and asks launchd for the daemon back on its third failed dial.
  func testAStopPressedInsideAStartLeavesTheServiceStopped() async throws {
    let registrar = SlowLaunchdRegistrar(registering: .milliseconds(100), stopping: .milliseconds(300))
    let client = DaemonClient(transport: VanishingTransport(), registrar: registrar, backoff: [.milliseconds(5)])
    defer { client.stop() }

    let starting = Task { await client.startService() }
    try await waitUntil("the start to reach launchd") { registrar.isRegistering }
    await client.stopService()
    await starting.value

    // Long enough for a stream the Start left behind to fail its way to the third dial that asks
    // launchd for the daemon back.
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(client.connection, .stopped)
    XCTAssertNil(client.state, "a stopped service has no phase to show")
    XCTAssertEqual(registrar.registrations, 1, "the loop asked launchd for the service the user stopped")
  }

  /// The mirror, where the Start finishes last. It is the later of the two presses, so it is the
  /// one that decides the outcome; the Stop must not write its own ending over it.
  func testAStartPressedInsideAStopLeavesTheServiceRunning() async throws {
    let registrar = SlowLaunchdRegistrar(registering: .milliseconds(100), stopping: .milliseconds(300))
    let client = DaemonClient(transport: CountingStateTransport(), registrar: registrar)
    defer { client.stop() }

    let stopping = Task { await client.stopService() }
    try await waitUntil("the stop to reach launchd") { registrar.isStopping }
    await client.startService()
    await stopping.value

    XCTAssertNotEqual(client.connection, .stopped)
    try await waitUntil("the restarted client to reach the daemon") { client.connection == .connected }
  }

  /// A Start that a Stop has already overtaken opens no stream. The Stop is the later press, so it
  /// has decided there is none; a stream opened anyway dials, and asks launchd for the daemon on
  /// its third failure, until the Stop's turn comes to drop it, and how soon that turn comes is
  /// up to a scheduler that a loaded machine spends elsewhere.
  func testAStartOvertakenByAStopOpensNoStream() async throws {
    let registrar = SlowLaunchdRegistrar(registering: .milliseconds(100), stopping: .milliseconds(10))
    let transport = CountingTransport()
    let client = DaemonClient(transport: transport, registrar: registrar)
    defer { client.stop() }

    let starting = Task { await client.startService() }
    try await waitUntil("the start to reach launchd") { registrar.isRegistering }
    await client.stopService()
    await starting.value

    XCTAssertEqual(transport.streamsOpened, 0, "the overtaken start dialled the daemon")
  }

  /// A press drops the stream when it is pressed, not when its turn comes. Between the two the
  /// loop is still live, and a loop mid-outage can reach its third failed dial in that gap and ask
  /// launchd for the service the user is stopping.
  func testPressingStopDropsTheStreamAtThePress() async throws {
    let transport = HeldStreamTransport()
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar())
    client.start()
    defer { client.stop() }
    // The task list is published in the same main-actor turn that goes back to wait on the
    // stream, so once it is here the loop is parked there and a cancel reaches the stream at once.
    try await waitUntil("the task list to arrive") { !client.tasks.active.isEmpty }

    // Queued before the press, so it runs ahead of the press's own task: in the gap between the
    // press and its turn.
    let endedBeforeTheVerbRan = Task { @MainActor in transport.isStreamEnded }
    await client.stopService()

    let ended = await endedBeforeTheVerbRan.value
    XCTAssertTrue(ended, "the stream outlived the press")
  }

}

// MARK: - SlowLaunchdRegistrar

/// A launchd stand-in whose calls take long enough for a second press to land inside them, the way
/// a real `bootstrap` and `bootout` do. The two durations are given separately because which of
/// the two verbs finishes last is the whole of the interleaving under test.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class SlowLaunchdRegistrar: LaunchAgentRegistrar, @unchecked Sendable {

  // MARK: Lifecycle

  init(registering: Duration, stopping: Duration) {
    registerDuration = registering
    stopDuration = stopping
  }

  // MARK: Internal

  var isRegistering: Bool {
    lock.withLock { registering }
  }

  var isStopping: Bool {
    lock.withLock { stopping }
  }

  var registrations: Int {
    lock.withLock { registered }
  }

  func ensureAgentRegistered() async throws {
    lock.withLock { registering = true }
    try? await Task.sleep(for: registerDuration)
    lock.withLock {
      registering = false
      registered += 1
    }
  }

  func stopAgent() async throws {
    lock.withLock { stopping = true }
    try? await Task.sleep(for: stopDuration)
    lock.withLock { stopping = false }
  }

  // MARK: Private

  private let registerDuration: Duration
  private let stopDuration: Duration
  private let lock = NSLock()
  private var registering = false
  private var stopping = false
  private var registered = 0

}

// MARK: - HeldStreamTransport

/// A daemon that answers the dial with a state frame, serves a one-task list, and holds the stream
/// open, recording when the client's end of the stream goes away.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class HeldStreamTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  var isStreamEnded: Bool {
    lock.withLock { ended }
  }

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data(Self.oneTaskJSON.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      continuation.onTermination = { _ in
        self.lock.withLock { self.ended = true }
      }
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
    }
  }

  // MARK: Private

  private static let oneTaskJSON =
    #"{"active":[{"id":1,"description":"write plan","done":false,"created_at":"2026-08-25T20:14:37Z","completed_at":"0001-01-01T00:00:00Z"}],"completed":[]}"#

  private let lock = NSLock()
  private var ended = false

}

import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - ServiceControlTests

/// Starting and stopping the timer service from the app (ADR-006). The registrar is a fake, so
/// nothing here registers or boots out a launchd agent on the machine running the tests.
@MainActor
final class ServiceControlTests: XCTestCase {

  func testStopServiceBootsTheAgentOutAndReportsTheServiceStopped() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stopService()

    XCTAssertEqual(registrar.calls, [.stop])
    XCTAssertEqual(client.connection, .stopped)
    XCTAssertNil(client.state, "a stopped service has no phase to show")
    XCTAssertNil(client.unresolvedError, "stopping on purpose is not an error")
  }

  func testStopServiceLeavesTheServiceAloneWhenLaunchdRefuses() async throws {
    let registrar = RecordingRegistrar(stopError: RecordingRegistrar.Denied())
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stopService()

    XCTAssertNotEqual(client.connection, .stopped, "a refused stop must not claim the service is stopped")
    XCTAssertNotNil(client.state)
    XCTAssertEqual(client.unresolvedError, "The timer service could not be stopped.")
  }

  func testStartServiceRegistersTheAgentAndLeavesTheStoppedState() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }
    client.stopService()

    client.startService()

    XCTAssertEqual(registrar.calls, [.stop, .register])
    XCTAssertNotEqual(client.connection, .stopped)
    try await waitUntil("the initial state to arrive") { client.state != nil }
  }

  /// The guarantee the whole control rests on: once launchd has been told to unload the agent,
  /// the reconnect loop must not quietly ask for it back. Asserting straight after `stopService()`
  /// would pass on a live loop too, so this waits out several backoff steps first.
  func testAStoppedServiceIsNotRevivedByTheReconnectLoop() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar, backoff: [.milliseconds(10)])
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stopService()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(registrar.calls, [.stop], "the loop asked launchd for the daemon again")
    XCTAssertEqual(client.connection, .stopped)
    XCTAssertNil(client.state)
  }

  /// ADR-006's central promise: the daemon is deliberately independent of any client, so the
  /// teardown a quitting app runs must never reach launchd.
  func testTearingTheClientDownDoesNotStopTheService() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stop()

    XCTAssertEqual(registrar.calls, [])
    XCTAssertNotEqual(client.connection, .stopped)
  }

}

// MARK: - ServiceActionsTests

final class ServiceActionsTests: XCTestCase {
  func testStopIsOfferedWhileTheServiceIsOnItsWayUpOrRunning() {
    for status in [ServiceStatus.running, .reaching] {
      XCTAssertEqual(ServiceActions.startOrStop(status: status), .stop, "\(status)")
    }
  }

  func testStartIsOfferedOnceTheServiceIsStopped() {
    XCTAssertEqual(ServiceActions.startOrStop(status: .stopped), .start)
  }

  /// The other two situations whose way out is Start, which is why each one's sentence can point
  /// at this single control instead of growing a retry button of its own.
  func testStartIsOfferedWhenLaunchdRefusedOrTheDaemonNeverArrived() {
    XCTAssertEqual(ServiceActions.startOrStop(status: .launchRefused), .start)
    XCTAssertEqual(ServiceActions.startOrStop(status: .notAnswering), .start)
  }

  func testTitlesSayWhatPressingThemDoes() {
    XCTAssertEqual(ServiceAction.start.title, "Start Timer Service")
    XCTAssertEqual(ServiceAction.stop.title, "Stop Timer Service")
  }
}

// MARK: - StubStateTransport

/// A daemon that serves one idle frame and holds the stream open, the way a live one does
/// between state changes.
struct StubStateTransport: DaemonTransport {
  let frame = Data(StateDecodingTests.idleJSON.utf8)

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data(#"{"active":[],"done":[]}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(frame)
    }
  }
}

// MARK: - EndOfDayActionTests

/// throwntom-azb: ending the work day is a first-class verb, not a corner of the idle state.
final class EndOfDayActionTests: XCTestCase {
  func testTheEndOfDayVerbSaysWhatItDoes() {
    XCTAssertEqual(TimerAction.skipToday.title, "Done for Today")
  }

  /// The daemon accepts skip-today whatever the timer is doing (internal/core/commands.go has no
  /// state guard on it), and the user who is finished has to be able to say so mid-pomodoro.
  func testEndingTheDayIsOfferedInEveryState() {
    let phases: [DaemonState.Phase] = [.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused]
    for phase in phases {
      let available = TimerActions.available(for: makeClientState(phase: phase))
      XCTAssertTrue(available.contains(.skipToday), "\(phase) should offer the end-of-day verb")
    }
  }

  func testEndingTheDayIsNeverThePrimaryVerb() {
    for phase in [DaemonState.Phase.idle, .work, .paused, .awaitingConfirm] {
      let available = TimerActions.available(for: makeClientState(phase: phase))
      XCTAssertNotEqual(available.first, .skipToday, "\(phase)")
    }
  }

  /// Offering the verb on the screen it already produced is a chip that does nothing. It belongs
  /// in every phase, not in the state it leaves behind.
  func testEndingTheDayIsNotOfferedOnceTheDayHasEnded() {
    let available = TimerActions.available(for: makeClientState(phase: .idle, dayEnded: true))
    XCTAssertFalse(available.contains(.skipToday))
    XCTAssertEqual(available, [.start, .newCycle])
  }

  func testAnEndedDayIsReadableFromTheDaemonState() {
    XCTAssertTrue(makeClientState(phase: .idle, dayEnded: true).dayEnded)
    XCTAssertFalse(makeClientState(phase: .idle).dayEnded)
  }
}

// MARK: - RefusedLaunchTests

/// throwntom-jtx: when launchd will not start the daemon the window must say so and say what to
/// do about it, rather than reporting a start that has definitively failed as still in progress.
@MainActor
final class RefusedLaunchTests: XCTestCase {
  func testTheNoteNamesLaunchdAndTheControlThatRetriesIt() async throws {
    let client = DaemonClient(
      transport: OutageTransport(),
      registrar: RecordingRegistrar(registerError: RecordingRegistrar.Denied()),
      backoff: [.milliseconds(10)],
    )
    client.start()
    defer { client.stop() }

    try await waitUntil("the refused launch to be reported") { client.registrationError != nil }

    let note = try XCTUnwrap(client.registrationError)
    XCTAssertTrue(note.contains("launchd"), note)
    XCTAssertTrue(note.contains(ServiceAction.start.title), note)
    XCTAssertEqual(client.unresolvedError, note)
  }

  /// throwntom-ejk: the window stops *showing* the retained state once launchd has refused, but
  /// the client must go on *holding* it — `AppMenus` and `ShortcutSheet` build the Timer menu
  /// from it, and clearing it here is the tempting shortcut to a disconnected-looking window.
  /// Snapping the presentation is `MainWindowContent`'s job; this asserts the state survives
  /// underneath it.
  ///
  /// A regression guard, not a red test: it passes on the pre-fix code too, because the fix is
  /// confined to the view layer. It exists so that a later "just clear the state" shortcut fails.
  func testARefusedLaunchKeepsTheRetainedStateForTheReconnect() async throws {
    let client = DaemonClient(
      transport: VanishingTransport(),
      registrar: RecordingRegistrar(registerError: RecordingRegistrar.Denied()),
      backoff: [.milliseconds(5)],
    )
    client.start()
    defer { client.stop() }
    try await waitUntil("the initial state to arrive") { client.state != nil }

    try await waitUntil("the refused launch to be reported") { client.registrationError != nil }

    XCTAssertNotNil(client.state, "the menus and shortcut sheet still read this")
  }
}

// MARK: - VanishingTransport

/// A daemon that answers one dial and is gone by the next: the first event stream serves a state
/// frame and ends, every later one fails. The shape of a daemon that dies while the app watches,
/// which is what puts a retained state and a failing reconnect in the client at the same time.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class VanishingTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  /// The task fetch belongs to the one dial that succeeds: the client runs it after decoding the
  /// frame, while that first stream is still the open one. Every later dial finds nothing.
  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    guard lock.withLock({ streamsOpened == 1 }) else {
      throw Self.gone
    }
    return HTTPResponse(status: 200, headers: [:], body: Data(#"{"active":[],"done":[]}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    let isFirst = lock.withLock {
      streamsOpened += 1
      return streamsOpened == 1
    }
    return AsyncThrowingStream { continuation in
      guard isFirst else {
        continuation.finish(throwing: Self.gone)
        return
      }
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
      // Ending it, rather than holding it open the way the other fakes do, is what sends the
      // client back round the reconnect loop to find the daemon gone.
      continuation.finish()
    }
  }

  // MARK: Private

  private static let gone = DaemonError.transport("POSIXErrorCode(rawValue: 2): No such file or directory")

  private let lock = NSLock()

  /// How many event streams the client has asked for. The daemon is alive during the first.
  private var streamsOpened = 0

}

// MARK: - RestartAfterStopTests

/// Pressing Start has to behave like a cold launch, not like a client that has lost a daemon:
/// the daemon it knew is gone, and launchd takes a moment, so the dialling that follows must be
/// as quiet as the app's own first dial.
@MainActor
final class RestartAfterStopTests: XCTestCase {

  // MARK: Internal

  func testStartingAfterAStopIsAsQuietAsAColdLaunch() async throws {
    let transport = StoppableTransport()
    // One long step, so the client parks in `reconnecting` where the assertions can see it
    // instead of racing through the attempts.
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar(), backoff: [.seconds(30)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the initial state to arrive") { client.state != nil }

    // Stopping the service really does take the socket away, so the dials that follow fail.
    transport.takeDown()
    client.stopService()
    client.startService()

    // The failure is what proves the loop actually dialled and parked, rather than the assertions
    // reading the connection `startService` set on its way in.
    try await waitUntil("the reconnect loop to park after its first failed dial") { client.lastError != nil }
    XCTAssertEqual(client.connection, .connecting, "the daemon this client knew is gone, so this is a first dial")
    XCTAssertNil(client.unresolvedError, "a start the user just asked for must not report the outage it is fixing")
    XCTAssertFalse(client.hasConnected, "the daemon the client knew is gone")
  }

  /// The control the refused-launch note points at has to dial now. The reconnect loop is parked
  /// in its backoff at that moment, so re-registering alone leaves the user pressing a button
  /// that does nothing until the sleep runs out.
  func testStartingAfterARefusedLaunchDialsWithoutWaitingOutTheBackoff() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(
      transport: transport,
      registrar: RecordingRegistrar(registerError: RecordingRegistrar.Denied()),
      backoff: Self.parkedAfterRefusal,
    )
    client.start()
    defer { client.stop() }
    try await waitUntil("the refused launch to park in startingDaemon") { client.connection == .startingDaemon }

    // launchd will take it now; the parked loop must not be what decides when we find out.
    transport.recover()
    client.startService()

    try await waitUntil("the retried start to connect", timeout: 3) { client.connection == .connected }
  }

  // MARK: Private

  /// Short enough to reach the refusal quickly, then long enough that a client which waits its
  /// backoff out never dials again inside the test's timeout.
  private static let parkedAfterRefusal: [Duration] = [
    .milliseconds(10),
    .milliseconds(10),
    .seconds(30),
  ]

}

// MARK: - StoppableTransport

/// A daemon that answers until the test takes it away, the way stopping the service does.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class StoppableTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  func takeDown() {
    lock.withLock { isUp = false }
  }

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    guard lock.withLock({ isUp }) else {
      throw Self.gone
    }
    return HTTPResponse(status: 200, headers: [:], body: Data(#"{"active":[],"done":[]}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    let up = lock.withLock { isUp }
    return AsyncThrowingStream { continuation in
      guard up else {
        continuation.finish(throwing: Self.gone)
        return
      }
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
    }
  }

  // MARK: Private

  private static let gone = DaemonError.transport("POSIXErrorCode(rawValue: 2): No such file or directory")

  private let lock = NSLock()
  private var isUp = true

}

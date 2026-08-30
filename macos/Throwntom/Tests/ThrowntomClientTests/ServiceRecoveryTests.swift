import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - StalledStartTests

/// throwntom-azp. Once launchd has accepted the one request this client makes per outage, a
/// daemon that never arrives left the window on "Starting timer…" for ever: `registrationError`
/// is nil because the ask succeeded, so nothing contradicted the connection state. Asking launchd
/// again is not the answer — it boots out a daemon that may be starting — so saying so is.
@MainActor
final class StalledStartTests: XCTestCase {

  func testAnAcceptedLaunchThatNeverStartsADaemonIsReportedRatherThanShownAsStarting() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: OutageTransport(), registrar: registrar, backoff: [.milliseconds(5)])
    client.start()
    defer { client.stop() }

    try await waitUntil("the stalled start to be reported") { client.serviceStatus == .notAnswering }

    XCTAssertNil(client.registrationError, "launchd accepted the ask; this is not a refusal")
    XCTAssertEqual(registrar.registrations, 1, "the way out of a stalled start is not to ask launchd again")
  }

  /// The two must stay apart: one names launchd as having said no, the other says it said yes and
  /// nothing came. They point at different things to check.
  func testARefusedLaunchIsStillReportedAsARefusal() async throws {
    let client = DaemonClient(
      transport: OutageTransport(),
      registrar: RecordingRegistrar(registerError: RecordingRegistrar.Denied()),
      backoff: [.milliseconds(5)],
    )
    client.start()
    defer { client.stop() }

    try await waitUntil("the refused launch to be reported") { client.registrationError != nil }

    XCTAssertEqual(client.serviceStatus, .launchRefused)
  }

  func testADaemonThatTurnsUpClearsTheStalledStart() async throws {
    let transport = OutageTransport()
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar(), backoff: [.milliseconds(5)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the stalled start to be reported") { client.serviceStatus == .notAnswering }

    transport.recover()

    try await waitUntil("the daemon to answer") { client.serviceStatus == .running }
    XCTAssertFalse(client.startStalled)
  }

  func testPressingStartClearsTheStalledStart() async throws {
    let client = DaemonClient(transport: OutageTransport(), registrar: RecordingRegistrar(), backoff: [.milliseconds(5)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the stalled start to be reported") { client.serviceStatus == .notAnswering }

    client.startService()

    XCTAssertFalse(client.startStalled, "the user just asked again; nothing has stalled yet")
  }

}

// MARK: - BackoffRegistrationCountTests

/// How the client tells "launchd was asked a moment ago" from "launchd was asked and nothing has
/// happened since". Counted here rather than by wall clock so the reading is deterministic.
final class BackoffRegistrationCountTests: XCTestCase {

  // MARK: Internal

  func testNothingIsCountedUntilLaunchdAccepts() {
    var backoff = makeBackoff()
    backoff.recordFailure()

    XCTAssertNil(backoff.failuresSinceRegistration)
  }

  func testARefusedAskStartsNoCount() {
    var backoff = makeBackoff()
    for _ in 0..<3 {
      backoff.recordFailure()
      backoff.registerAgentIfDue { false }
    }

    XCTAssertNil(backoff.failuresSinceRegistration, "a refusal is reported as a refusal, not as a silent daemon")
  }

  func testTheDialsAfterAnAcceptedAskAreCounted() {
    var backoff = acceptedRegistration()

    XCTAssertEqual(backoff.failuresSinceRegistration, 0)
    backoff.recordFailure()
    backoff.registerAgentIfDue {
      XCTFail("at most one accepted ask per outage")
      return true
    }
    XCTAssertEqual(backoff.failuresSinceRegistration, 1)
    backoff.recordFailure()
    XCTAssertEqual(backoff.failuresSinceRegistration, 2)
  }

  func testAnAnsweringDaemonForgetsTheRegistration() {
    var backoff = acceptedRegistration()
    backoff.recordFailure()

    backoff.reset()

    XCTAssertNil(backoff.failuresSinceRegistration)
  }

  // MARK: Private

  private func makeBackoff() -> ReconnectBackoff {
    ReconnectBackoff(delays: [.milliseconds(1)], registerEvery: 3)
  }

  /// A backoff that has failed its way to one accepted registration, which is where the count starts.
  private func acceptedRegistration() -> ReconnectBackoff {
    var backoff = makeBackoff()
    for _ in 0..<3 {
      backoff.recordFailure()
      backoff.registerAgentIfDue { true }
    }
    return backoff
  }

}

// MARK: - CancelledRefreshTests

/// throwntom-7vo. `startService()` cancels the stream task, which may be suspended inside
/// `refreshTasks`. `SocketConnection` resumes a cancelled operation with `CancellationError`,
/// which is not a `DaemonError`, so it was reworded as an unreadable reply and written to
/// `lastError` — a fault note on the very screen the user had just pressed Start on.
@MainActor
final class CancelledRefreshTests: XCTestCase {

  /// The behaviour under test is that nothing happens, which is the hardest kind of assertion to
  /// place in time. It is placed by owning the task that runs the fetch: `await refreshing.value`
  /// returns only once `refreshTasks` has finished, `catch` included, so the assertion cannot run
  /// before the code it is about. No sleep, and no argument about which executor resumes what —
  /// an earlier version of this test reasoned that the main actor's queue ordered it and was
  /// wrong, because `DaemonTransport.request` is nonisolated: the continuation resumes on the
  /// cooperative pool and only then hops back, behind anything the test has already enqueued.
  func testACancelledTaskFetchLeavesNoFaultNote() async throws {
    let transport = ParkingTasksTransport()
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar(), backoff: [.seconds(30)])
    let refreshing = Task { await client.refreshTasks() }
    try await waitUntil("the task fetch to be in flight") { transport.isParked }

    refreshing.cancel()
    transport.releaseAsCancelled()
    await refreshing.value

    XCTAssertNil(client.lastError, "a fetch the client itself cancelled is not a reply it could not read")
    XCTAssertNil(client.unresolvedError)
  }

  /// Why the guard above is reachable at all: the fetch the stream runs after each frame is still
  /// outstanding when Start tears the stream down, so the cancellation lands inside it. Asserted on
  /// the transport, which knows whether it has answered, rather than on a moment in time.
  func testPressingStartCancelsATaskFetchThatIsStillInFlight() async throws {
    let transport = ParkingTasksTransport()
    let client = DaemonClient(transport: transport, registrar: RecordingRegistrar(), backoff: [.seconds(30)])
    client.start()
    defer { client.stop() }
    try await waitUntil("the task fetch to be in flight") { transport.isParked }

    client.startService()

    XCTAssertTrue(transport.isParked, "the fetch had not answered, so Start cancelled it mid-request")
  }

  /// The guard must not swallow a real failure: only a cancelled fetch is silent.
  func testAFetchThatReallyFailsIsStillReported() async throws {
    let client = DaemonClient(transport: FailingTasksTransport(), registrar: RecordingRegistrar(), backoff: [.seconds(30)])
    client.start()
    defer { client.stop() }

    try await waitUntil("the failed fetch to be reported") { client.lastError != nil }
  }

}

// MARK: - ParkingTasksTransport

/// A daemon whose first task fetch never answers until the test says so, and then answers the way
/// a cancelled socket operation does. That is what puts a suspended `refreshTasks` and a
/// `stop()` in the client at the same moment.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class ParkingTasksTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  var isParked: Bool {
    lock.withLock { parked != nil }
  }

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    let isFirst = lock.withLock {
      fetches += 1
      return fetches == 1
    }
    guard isFirst else {
      return Self.emptyTaskList
    }
    return try await withCheckedThrowingContinuation { continuation in
      lock.withLock { parked = continuation }
    }
  }

  /// Resumes the parked fetch exactly as `SocketConnection.perform` resumes a cancelled one.
  func releaseAsCancelled() {
    let continuation = lock.withLock {
      let held = parked
      parked = nil
      return held
    }
    continuation?.resume(throwing: CancellationError())
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
    }
  }

  // MARK: Private

  private static let emptyTaskList = HTTPResponse(status: 200, headers: [:], body: Data(#"{"active":[],"completed":[]}"#.utf8))

  private let lock = NSLock()
  private var fetches = 0
  private var parked: CheckedContinuation<HTTPResponse, Error>?

}

// MARK: - FailingTasksTransport

/// A daemon whose event stream works and whose task fetch does not: a real failure, not a
/// cancellation, so the client still has something to report.
struct FailingTasksTransport: DaemonTransport {
  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    throw DaemonError.http(status: 500, message: "the timer fell over")
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(Data(StateDecodingTests.idleJSON.utf8))
    }
  }
}

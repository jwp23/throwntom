import XCTest
@testable import ThrowntomClient

// MARK: - StallingTransport

/// A transport whose every request hangs until the calling task is cancelled, which is how a
/// cancelled request really ends: the socket resumes the suspended operation by throwing, and
/// `Task.sleep` throws the same `CancellationError` the socket does.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class StallingTransport: DaemonTransport, @unchecked Sendable {

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    try await Task.sleep(for: .seconds(60))
    return HTTPResponse(status: 200, headers: [:], body: Data())
  }

  /// Never yields and never ends, so a client built on it stays in its first dial rather than
  /// running the reconnect loop underneath whatever the test is actually about.
  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { _ in }
  }

}

// MARK: - CancelledWorkTests

/// Work this client itself cancelled is not a failure the user caused, so it leaves no note on
/// the window. `refreshTasks()` has always guarded for this; these cover the request paths that
/// did not (throwntom-esk).
@MainActor
final class CancelledWorkTests: XCTestCase {

  func testACancelledCommandLeavesNoRefusalOnTheWindow() async throws {
    let client = DaemonClient(transport: StallingTransport(), registrar: RecordingRegistrar())
    let inFlight = Task { try await client.command("status") }

    inFlight.cancel()
    let outcome = await inFlight.result

    XCTAssertThrowsError(try outcome.get(), "the command still fails; it just is not the user's failure")
    XCTAssertNil(client.commandError)
    XCTAssertNil(client.unresolvedError)
  }

  func testACancelledTimerVerbLeavesNoRefusalOnTheWindow() async {
    let client = DaemonClient(transport: StallingTransport(), registrar: RecordingRegistrar())
    let inFlight = Task { try await client.timer(.pause) }

    inFlight.cancel()
    _ = await inFlight.result

    XCTAssertNil(client.commandError)
  }

  /// The guard must not swallow real refusals with the cancelled ones: an uncancelled failure
  /// still has to reach the window, or the fix would read as passing by saying nothing ever.
  func testAnUncancelledFailureStillReachesTheWindow() async {
    let client = DaemonClient(transport: RefusingTransport(), registrar: RecordingRegistrar())

    _ = try? await client.command("status")

    XCTAssertEqual(client.commandError, "no such thing")
  }

}

// MARK: - RefusingTransport

/// A transport that answers every request with the daemon's own 409 refusal.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class RefusingTransport: DaemonTransport, @unchecked Sendable {

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 409, headers: [:], body: Data(#"{"error":"no such thing"}"#.utf8))
  }

  /// Never yields and never ends, so a client built on it stays in its first dial rather than
  /// running the reconnect loop underneath whatever the test is actually about.
  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { _ in }
  }

}

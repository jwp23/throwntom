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
    try await waitUntil { client.state != nil }

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
    try await waitUntil { client.state != nil }

    client.stopService()

    XCTAssertNotEqual(client.connection, .stopped, "a refused stop must not claim the service is stopped")
    XCTAssertNotNil(client.state)
    XCTAssertEqual(client.unresolvedError, "The timer service could not be stopped.")
  }

  func testStartServiceRegistersTheAgentAndLeavesTheStoppedState() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil { client.state != nil }
    client.stopService()

    client.startService()

    XCTAssertEqual(registrar.calls, [.stop, .register])
    XCTAssertNotEqual(client.connection, .stopped)
    try await waitUntil { client.state != nil }
  }

  /// ADR-006's central promise: the daemon is deliberately independent of any client, so the
  /// teardown a quitting app runs must never reach launchd.
  func testTearingTheClientDownDoesNotStopTheService() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)
    client.start()
    try await waitUntil { client.state != nil }

    client.stop()

    XCTAssertEqual(registrar.calls, [])
    XCTAssertNotEqual(client.connection, .stopped)
  }

}

// MARK: - ServiceActionsTests

final class ServiceActionsTests: XCTestCase {
  func testStopIsOfferedWhileTheServiceIsOnItsWayUpOrRunning() {
    let running: [DaemonClient.Connection] = [.connected, .connecting, .reconnecting(attempt: 1), .startingDaemon]
    for connection in running {
      XCTAssertEqual(
        ServiceActions.startOrStop(connection: connection, registrationFailed: false),
        .stop,
        "\(connection)",
      )
    }
  }

  func testStartIsOfferedOnceTheServiceIsStopped() {
    XCTAssertEqual(ServiceActions.startOrStop(connection: .stopped, registrationFailed: false), .start)
  }

  /// A refused launch is the other state whose way out is Start, which is why the failure note
  /// can point at this one control instead of growing a retry button of its own.
  func testStartIsOfferedWhenLaunchdRefusedToStartTheDaemon() {
    XCTAssertEqual(ServiceActions.startOrStop(connection: .startingDaemon, registrationFailed: true), .start)
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

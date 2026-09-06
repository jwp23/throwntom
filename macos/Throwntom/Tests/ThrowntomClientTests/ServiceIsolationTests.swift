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

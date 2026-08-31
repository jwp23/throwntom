import XCTest
@testable import ThrowntomClient

/// Every place the client itself catches a failure and tells the window a sentence instead of the
/// error. The sentence stays; what the error actually was now goes to the log (throwntom-zas).
@MainActor
final class ClientLoggingSitesTests: XCTestCase {

  func testARefusedStopRecordsWhyLaunchdSaidNo() throws {
    let recorder = LogRecorder()
    let client = DaemonClient(
      transport: StallingTransport(),
      registrar: RecordingRegistrar(stopError: NSError(domain: "SMAppServiceErrorDomain", code: 1)),
    )

    client.stopService()

    XCTAssertEqual(client.commandError, "The timer service could not be stopped.")
    let entry = try recorder.onlyEntry()
    XCTAssertEqual(entry.area, .service)
    XCTAssertEqual(entry.message, "stop the timer service failed: SMAppServiceErrorDomain 1")
  }

  func testARefusedRegistrationRecordsWhyLaunchdSaidNo() {
    let recorder = LogRecorder()
    let client = DaemonClient(
      transport: StallingTransport(),
      registrar: RecordingRegistrar(registerError: NSError(domain: "SMAppServiceErrorDomain", code: 2)),
    )

    client.startService()
    defer { client.stop() }

    XCTAssertNotNil(client.registrationError)
    XCTAssertTrue(
      recorder.messages.contains("register the launch agent failed: SMAppServiceErrorDomain 2"),
      "\(recorder.messages)",
    )
  }

  func testAFailedTaskRefreshRecordsTheTransportFailure() async throws {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: RefusingTransport(), registrar: RecordingRegistrar())

    await client.refreshTasks()

    XCTAssertEqual(client.lastError, "no such thing")
    let entry = try recorder.onlyEntry()
    XCTAssertEqual(entry.area, .tasks)
    XCTAssertEqual(entry.message, "refresh tasks failed: http 409")
  }

  /// A cancelled refresh is not a failure, so it must leave the log as quiet as it leaves the
  /// window. Logging it would fill the log with entries every Stop and Start produces by design.
  func testACancelledTaskRefreshRecordsNothing() async {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: StallingTransport(), registrar: RecordingRegistrar())

    let inFlight = Task { await client.refreshTasks() }
    inFlight.cancel()
    await inFlight.value

    XCTAssertEqual(recorder.entries, [])
  }

}

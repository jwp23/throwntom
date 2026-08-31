import XCTest
@testable import ThrowntomClient

// MARK: - ClientLoggingSitesTests

/// Every place the client itself catches a failure and tells the window a sentence instead of the
/// error. The sentence is what the reader gets; the log is where the error itself is kept.
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

  /// The window's whole account of a dropped stream is "Timer is restarting…", which is the same
  /// sentence whether the socket is gone, the daemon died mid-frame or a frame would not decode.
  /// The log is where those come apart.
  func testADroppedEventStreamRecordsWhyTheTimerIsRestarting() async throws {
    let recorder = LogRecorder()
    // One long backoff step: the loop records its first failure and then parks, so the assertion
    // reads a single entry rather than racing a loop that is still redialling.
    let client = DaemonClient(
      transport: DroppedStreamTransport(),
      registrar: RecordingRegistrar(),
      backoff: [.seconds(30)],
    )

    client.start()
    defer { client.stop() }
    try await waitUntil("the dropped stream to be recorded") { !recorder.entries.isEmpty }

    XCTAssertEqual(recorder.entries.first?.area, .daemon)
    XCTAssertEqual(recorder.messages.first, "read the event stream failed: transport: dropped")
  }

}

// MARK: - DroppedStreamTransport

/// A daemon whose event stream fails the moment it is dialled, the way a missing socket or a
/// daemon that died mid-frame ends one.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class DroppedStreamTransport: DaemonTransport, @unchecked Sendable {

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    throw DaemonError.transport("dropped")
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish(throwing: DaemonError.transport("dropped")) }
  }

}

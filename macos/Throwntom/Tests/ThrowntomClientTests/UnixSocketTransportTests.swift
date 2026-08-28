import XCTest
@testable import ThrowntomClient

final class UnixSocketTransportTests: XCTestCase {

  // MARK: Internal

  override func setUp() async throws {
    daemon = try DaemonHarness()
    try await daemon.start()
    transport = UnixSocketTransport(socketPath: daemon.socketPath)
  }

  override func tearDown() {
    daemon?.cleanup()
  }

  func testGetStateReturnsDecodableJSON() async throws {
    let response = try await transport.request("GET", "/v1/state", body: nil)
    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(response.headers["content-type"], "application/json")
    let state = try DaemonJSON.decoder.decode(DaemonState.self, from: response.body)
    XCTAssertEqual(state.state, .idle)
  }

  func testPostCommandUsageErrorIs400WithErrorBody() async throws {
    let body = Data(#"{"line":"bogus"}"#.utf8)
    let response = try await transport.request("POST", "/v1/command", body: body)
    XCTAssertEqual(response.status, 400)
    XCTAssertEqual(String(decoding: response.body, as: UTF8.self), #"{"error":"unknown command: bogus"}"# + "\n")
  }

  func testEventsYieldInitialStateThenUpdates() async throws {
    let log = FrameLog()
    let consumer = log.consume(transport.events("/v1/events"))
    defer { consumer.cancel() }
    try await waitUntil { log.frames.count >= 1 }
    XCTAssertEqual(log.frames[0].state, .idle)

    let body = Data(#"{"line":"task add hello"}"#.utf8)
    let response = try await transport.request("POST", "/v1/command", body: body)
    XCTAssertEqual(response.status, 200)
    try await waitUntil { log.frames.count >= 2 }
    XCTAssertNil(log.error)
  }

  func testEventsFinishWithErrorWhenDaemonStops() async throws {
    let log = FrameLog()
    let consumer = log.consume(transport.events("/v1/events"))
    defer { consumer.cancel() }
    try await waitUntil { log.frames.count >= 1 }
    daemon.stop()
    try await waitUntil { log.error != nil }
  }

  func testMissingSocketFailsQuickly() async throws {
    let missing = UnixSocketTransport(socketPath: daemon.home.appendingPathComponent("nope.sock").path)
    let started = Date()
    do {
      _ = try await missing.request("GET", "/v1/state", body: nil)
      XCTFail("expected a transport error")
    } catch let error as DaemonError {
      guard case .transport = error else { return XCTFail("unexpected \(error)") }
    }
    XCTAssertLessThan(Date().timeIntervalSince(started), 2)
  }

  // MARK: Private

  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var daemon: DaemonHarness!
  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var transport: UnixSocketTransport!

}

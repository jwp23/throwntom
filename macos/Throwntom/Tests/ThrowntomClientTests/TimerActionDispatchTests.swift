import XCTest
@testable import ThrowntomClient

// MARK: - RecordingTransport

/// Answers every request from memory and remembers what was asked, so the routing a timer
/// action performs can be checked without a daemon.
// `recorded` is only touched under `lock`; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class RecordingTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Lifecycle

  init(status: Int = 200) {
    self.status = status
  }

  // MARK: Internal

  struct Request: Equatable {
    var method: String
    var path: String
    var body: Data?
  }

  var requests: [Request] {
    lock.withLock { recorded }
  }

  func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
    lock.withLock { recorded.append(Request(method: method, path: path, body: body)) }
    return HTTPResponse(status: status, headers: [:], body: Data(#"{"message":"ok"}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish(throwing: DaemonError.transport("no event stream")) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var recorded = [Request]()
  private let status: Int

}

// MARK: - TimerActionDispatchTests

@MainActor
final class TimerActionDispatchTests: XCTestCase {

  // MARK: Internal

  func testVerbActionsPostTheirOwnTimerPathWithNoBody() async throws {
    let (client, transport) = makeClient()
    for action in TimerAction.allCases where action.verb != nil {
      try await client.perform(action)
    }
    XCTAssertEqual(transport.requests.map(\.path), [
      "/v1/timer/start",
      "/v1/timer/confirm",
      "/v1/timer/pause",
      "/v1/timer/resume",
      "/v1/timer/skip",
      "/v1/timer/skip-today",
      "/v1/timer/new-cycle",
    ])
    XCTAssertEqual(Set(transport.requests.map(\.method)), ["POST"])
    XCTAssertEqual(transport.requests.compactMap(\.body), [])
  }

  func testSnoozeGoesToItsOwnEndpointWithTheDefaultMinutes() async throws {
    let (client, transport) = makeClient()
    try await client.perform(.snooze)
    XCTAssertEqual(transport.requests.map(\.path), ["/v1/timer/snooze"])
    let body = try XCTUnwrap(transport.requests.first?.body)
    XCTAssertEqual(
      try JSONSerialization.jsonObject(with: body) as? [String: Int],
      ["minutes": TimerActions.defaultSnoozeMinutes],
    )
  }

  func testRefusalPropagatesSoCallersCanBeep() async throws {
    let (client, _) = makeClient(status: 409)
    do {
      try await client.perform(.pause)
      XCTFail("a refused verb must throw")
    } catch DaemonError.http(let status, _) {
      XCTAssertEqual(status, 409)
    }
  }

  // MARK: Private

  private func makeClient(status: Int = 200) -> (client: DaemonClient, transport: RecordingTransport) {
    let transport = RecordingTransport(status: status)
    return (DaemonClient(transport: transport, registrar: RecordingRegistrar()), transport)
  }

}

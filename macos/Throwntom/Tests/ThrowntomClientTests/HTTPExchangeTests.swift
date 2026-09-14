import XCTest
@testable import ThrowntomClient

/// What `request` puts on the wire and what it makes of what comes back. `UnixSocketTransportTests`
/// drives the same code against a real daemon, which answers the one way it feels like: it cannot
/// be asked for a body longer than its own Content-Length, a chunked reply, or a head that never
/// finishes arriving.
final class HTTPExchangeTests: XCTestCase {

  // MARK: Internal

  override func setUpWithError() throws {
    server = try ScriptedSocketServer()
    transport = UnixSocketTransport(socketPath: try XCTUnwrap(server).path)
  }

  override func tearDown() {
    server?.stop()
    server = nil
  }

  func testARequestAsksForJSONOverAConnectionTheDaemonCloses() throws {
    let server = try XCTUnwrap(server)
    let answered = try inFlightRequest("GET", "/v1/state", body: nil)
    defer { answered.cancel() }

    let head = try server.requestHead()

    XCTAssertEqual(head.components(separatedBy: "\r\n"), [
      "GET /v1/state HTTP/1.1",
      "Host: throwntomd",
      "Connection: close",
      "Accept: application/json",
    ])
  }

  func testARequestWithABodySendsItBehindItsTypeAndLength() async throws {
    let server = try XCTUnwrap(server)
    let body = Data(#"{"line":"status"}"#.utf8)
    let answered = try inFlightRequest("POST", "/v1/command", body: body)
    defer { answered.cancel() }

    let head = try server.requestHead()

    XCTAssertEqual(head.components(separatedBy: "\r\n"), [
      "POST /v1/command HTTP/1.1",
      "Host: throwntomd",
      "Connection: close",
      "Accept: application/json",
      "Content-Type: application/json",
      "Content-Length: \(body.count)",
    ])
    try await waitUntil("the body to arrive") { server.received.count >= head.utf8.count + 4 + body.count }
    XCTAssertEqual(server.received.suffix(body.count), body)
  }

  /// A response body is whatever Content-Length says it is. The daemon's keep-alive replies can
  /// carry the start of the next one behind it, and that is not this response's.
  func testAResponseBodyIsCutToItsContentLength() async throws {
    let server = try XCTUnwrap(server)
    let answered = try inFlightRequest("GET", "/v1/state", body: nil)
    _ = try server.requestHead()

    try server.reply("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 4\r\n\r\ntrueAND MORE")
    try server.endReply()

    let response = try await answered.value
    XCTAssertEqual(response.status, 200)
    XCTAssertEqual(response.headers["content-type"], "application/json")
    XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "true")
  }

  func testAChunkedResponseIsDecodedIntoItsBody() async throws {
    let server = try XCTUnwrap(server)
    let answered = try inFlightRequest("GET", "/v1/state", body: nil)
    _ = try server.requestHead()

    try server.reply("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
    try server.reply(Self.chunk("tr") + Self.chunk("ue") + "0\r\n\r\n")
    try server.endReply()

    let response = try await answered.value
    XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "true")
  }

  func testAResponseThatEndsBeforeItsHeadersFails() async throws {
    let server = try XCTUnwrap(server)
    let answered = try inFlightRequest("GET", "/v1/state", body: nil)
    _ = try server.requestHead()

    try server.reply("HTTP/1.1 200 OK\r\nContent-Ty")
    try server.endReply()

    do {
      _ = try await answered.value
      XCTFail("a half-sent response was accepted")
    } catch {
      XCTAssertEqual(error as? DaemonError, .malformedResponse("response ended before headers completed"))
    }
  }

  /// One connection per request: the transport hangs up on its way out rather than leaving a
  /// socket open for a daemon that has already answered.
  func testTheConnectionIsClosedOnceTheRequestIsAnswered() async throws {
    let server = try XCTUnwrap(server)
    let answered = try inFlightRequest("GET", "/v1/state", body: nil)
    _ = try server.requestHead()
    try server.reply("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    try server.endReply()
    _ = try await answered.value

    try await waitUntil("the client to hang up") { server.closedByClient >= 1 }
  }

  // MARK: Private

  private var server: ScriptedSocketServer?
  // XCTest builds fixtures in setUp, after init, so the property cannot be initialised there.
  // swiftlint:disable:next implicitly_unwrapped_optional
  private var transport: UnixSocketTransport!

  private static func chunk(_ text: String) -> String {
    String(text.utf8.count, radix: 16) + "\r\n" + text + "\r\n"
  }

  /// Starts the request and leaves it running, so the test can watch what arrived at the peer
  /// before deciding what to answer with.
  private func inFlightRequest(_ method: String, _ path: String, body: Data?) throws -> Task<HTTPResponse, Error> {
    let transport = try XCTUnwrap(transport)
    return Task { try await transport.request(method, path, body: body) }
  }

}

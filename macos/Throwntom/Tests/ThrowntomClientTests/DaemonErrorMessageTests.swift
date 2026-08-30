import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - GatewayFailureTransport

/// A daemon answering the way a proxy in front of it would: a failing status and a body that is
/// not the daemon's own `{"error":…}` reply.
struct GatewayFailureTransport: DaemonTransport {
  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 502, headers: [:], body: Data("<html><body>502 Bad Gateway</body></html>".utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish() }
  }
}

// MARK: - DaemonErrorMessageTests

/// The window renders these strings verbatim, so each one has to read as a sentence a reader
/// can act on rather than as the error's own description.
final class DaemonErrorMessageTests: XCTestCase {

  // MARK: Internal

  func testATransportFailureReadsAsARestart() {
    let outage = DaemonError.transport("POSIXErrorCode(rawValue: 2): No such file or directory")

    XCTAssertEqual(outage.userMessage, "Timer is restarting…")
  }

  func testARefusalKeepsTheDaemonsOwnWords() {
    let refusal = DaemonError.http(status: 409, message: "nothing to snooze: no reminder is outstanding")

    XCTAssertEqual(refusal.userMessage, "nothing to snooze: no reminder is outstanding")
  }

  func testATimeoutSaysTheTimerIsNotAnswering() {
    XCTAssertEqual(DaemonError.timedOut(after: .seconds(5)).userMessage, "The timer is not responding.")
  }

  func testAMalformedReplyDoesNotShowTheParserError() {
    let garbled = DaemonError.malformedResponse("response ended before headers completed")

    XCTAssertEqual(garbled.userMessage, "The timer sent a reply we could not read.")
  }

  func testARefusalTheDaemonExplainsKeepsItsWords() {
    let reply = Data(#"{"error":"nothing to snooze: no reminder is outstanding"}"#.utf8)

    XCTAssertEqual(DaemonClient.errorMessage(reply), "nothing to snooze: no reminder is outstanding")
  }

  /// A body that is not the daemon's own error reply — a proxy's HTML page, an empty body, an
  /// `error` field with nothing in it — is not a sentence, and the window renders these verbatim.
  /// An empty field is the one that would otherwise read as a blank failure.
  func testABodyThatExplainsNothingNeverReachesTheReader() {
    let bodies = [
      "<html><body>502 Bad Gateway</body></html>",
      "",
      "Internal Server Error",
      #"{"error":""}"#,
      #"{"error":"   \n"}"#,
      #"{"message":"ok"}"#,
    ]

    for body in bodies {
      XCTAssertEqual(
        DaemonClient.errorMessage(Data(body.utf8)),
        "The timer sent an error it did not explain.",
        "\(body)",
      )
    }
  }

  /// The wiring, not just the wording: a gateway body travels the real path a user's command
  /// takes — `perform` → `check` → `errorMessage` → `DaemonError.http.userMessage` → the
  /// `commandError` the window renders — and the body itself is nowhere in what comes out.
  @MainActor
  func testAGatewayBodyReachesTheWindowAsASentenceAndNotAsItself() async throws {
    let client = DaemonClient(transport: GatewayFailureTransport(), registrar: RefusingRegistrar())

    do {
      try await client.perform(.start)
      XCTFail("a 502 is not a started timer")
    } catch let error as DaemonError {
      XCTAssertEqual(error, .http(status: 502, message: "The timer sent an error it did not explain."))
    }

    XCTAssertEqual(client.commandError, "The timer sent an error it did not explain.")
    XCTAssertFalse(try XCTUnwrap(client.commandError).contains("html"), "the body never reaches the window")
  }

  func testNoMessageLeaksTheErrorsOwnDescription() {
    for error in Self.everyCase {
      XCTAssertFalse(error.userMessage.contains("DaemonError"), "\(error) leaks its type")
      XCTAssertFalse(error.userMessage.contains("POSIXErrorCode"), "\(error) leaks the socket error")
    }
  }

  // MARK: Private

  private static let everyCase: [DaemonError] = [
    .transport("POSIXErrorCode(rawValue: 2): No such file or directory"),
    .malformedResponse("response ended before headers completed"),
    .http(status: 409, message: "nothing to snooze"),
    .timedOut(after: .seconds(5)),
  ]

}

import XCTest
@testable import ThrowntomClient

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

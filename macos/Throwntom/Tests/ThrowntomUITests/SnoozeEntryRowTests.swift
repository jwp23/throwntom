import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeEntryRowTests: XCTestCase {

  // MARK: Internal

  func testAWholeNumberOfMinutesIsSnoozedAndClosesTheField() throws {
    let (row, transport, model, refusals) = try makeRow()
    row.submit("45")

    XCTAssertEqual(refusals.count, 0, "a valid duration must not beep")
    XCTAssertFalse(model.isEnteringSnooze, "the field closes once it is answered")
    try waitForRequest(transport)
    XCTAssertEqual(
      transport.requests,
      [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":45}"#)],
    )
  }

  /// A refusal keeps the field open with the text intact: the user mistyped, and retyping from
  /// scratch is a worse answer than correcting.
  func testARefusedDurationBeepsAndLeavesTheFieldOpen() throws {
    for entry in ["", "  ", "0", "-1", "abc", "1.5", "90m", "99999"] {
      let (row, transport, model, refusals) = try makeRow()
      row.submit(entry)
      XCTAssertEqual(refusals.count, 1, entry)
      XCTAssertTrue(model.isEnteringSnooze, entry)
      XCTAssertEqual(transport.requests.count, 0, entry)
    }
  }

  // MARK: Private

  /// A counter the row can report a refusal into, so the beep is observable.
  private final class RefusalLog {
    var count = 0
  }

  private func makeRow() throws -> (SnoozeEntryRow, StubTransport, WindowModel, RefusalLog) {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    let model = environment.windowModel
    model.isEnteringSnooze = true
    let refusals = RefusalLog()
    let row = SnoozeEntryRow(client: environment.client, model: model) { refusals.count += 1 }
    return (row, transport, model, refusals)
  }

  private func waitForRequest(_ transport: StubTransport) throws {
    let deadline = Date().addingTimeInterval(2)
    while transport.requests.isEmpty, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

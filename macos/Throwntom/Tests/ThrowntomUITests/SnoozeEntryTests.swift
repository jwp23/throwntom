import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeEntryTests: XCTestCase {

  func testAWholeNumberOfMinutesIsSnoozed() {
    XCTAssertEqual(SnoozeEntry.commit("45"), .snooze(minutes: 45))
  }

  func testAnythingElseIsRefusedRatherThanGuessedAt() {
    for entry in ["", "  ", "0", "-1", "abc", "1.5", "90m", "99999"] {
      XCTAssertEqual(SnoozeEntry.commit(entry), .refuse, entry)
    }
  }

  /// Escape closes the duration field before anything else, so the field the user is typing in is
  /// always what Escape answers — otherwise it would shut the panel behind it and leave the field.
  func testEscapeClosesTheDurationFieldFirst() {
    let model = WindowModel()
    model.panel = .tasks
    model.showsShortcuts = true
    model.isEnteringSnooze = true

    XCTAssertTrue(model.dismiss())
    XCTAssertFalse(model.isEnteringSnooze)
    XCTAssertTrue(model.showsShortcuts, "the sheet should still be open")
    XCTAssertEqual(model.panel, .tasks, "the panel should still be open")
  }

  func testTheDurationFieldStartsClosed() {
    XCTAssertFalse(WindowModel().isEnteringSnooze)
  }

}

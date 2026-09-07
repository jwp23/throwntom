import XCTest
@testable import ThrowntomUI

@MainActor
final class WindowModelTests: XCTestCase {
  func testToggleOpensAndClosesTheSamePanel() {
    let model = WindowModel()
    model.toggle(.tasks)
    XCTAssertEqual(model.panel, .tasks)
    model.toggle(.tasks)
    XCTAssertNil(model.panel)
  }

  func testToggleSwitchesPanels() {
    let model = WindowModel()
    model.toggle(.tasks)
    model.toggle(.stats)
    XCTAssertEqual(model.panel, .stats)
  }

  func testDismissClosesSheetBeforePanel() {
    let model = WindowModel()
    model.toggle(.stats)
    model.showsShortcuts = true
    XCTAssertTrue(model.dismiss(panelIsShown: true))
    XCTAssertFalse(model.showsShortcuts)
    XCTAssertEqual(model.panel, .stats)
    XCTAssertTrue(model.dismiss(panelIsShown: true))
    XCTAssertNil(model.panel)
    XCTAssertFalse(model.dismiss(panelIsShown: true), "nothing left to close")
  }

  /// A panel the window is declining to draw — the service is down — is not something Escape can
  /// close, so it must not swallow the keystroke. Otherwise the first Escape on a service-down
  /// window does nothing visible and never reaches the task edit it was meant to cancel, and the
  /// user cannot clear the panel by hand either: the chips and menu items that toggle it are
  /// withdrawn on that screen.
  func testAPanelTheWindowIsNotDrawingDoesNotSwallowEscape() {
    let model = WindowModel()
    model.toggle(.tasks)

    XCTAssertFalse(model.dismiss(panelIsShown: false), "the edit cancel behind this never ran")
    XCTAssertEqual(model.panel, .tasks, "it comes back with the daemon rather than needing reopening")
  }

  func testTheSheetStillClosesOverAnUndrawnPanel() {
    let model = WindowModel()
    model.toggle(.tasks)
    model.showsShortcuts = true

    XCTAssertTrue(model.dismiss(panelIsShown: false), "the cheat sheet is on screen and is local")
    XCTAssertFalse(model.showsShortcuts)
  }

  /// Escape answers the duration field before the sheet or the panel, so it always closes
  /// whatever the user is actually looking at.
  func testDismissClosesTheSnoozeFieldBeforeEverythingElse() {
    let model = WindowModel()
    model.panel = .tasks
    model.showsShortcuts = true
    model.isEnteringSnooze = true

    XCTAssertTrue(model.dismiss(panelIsShown: true))
    XCTAssertFalse(model.isEnteringSnooze)
    XCTAssertTrue(model.showsShortcuts, "the sheet should still be open")
    XCTAssertEqual(model.panel, .tasks, "the panel should still be open")
  }

  func testTheSnoozeFieldStartsClosed() {
    XCTAssertFalse(WindowModel().isEnteringSnooze)
  }

  /// beginEntry(_:) ensures mutual exclusion: opening one entry field closes all others.
  /// This is critical when menu bar actions switch between fields without closing the current one first.
  func testBeginEntryLunchClosesOtherEntries() {
    let model = WindowModel()
    model.isEnteringSnooze = true
    model.isEnteringMeeting = true

    model.beginEntry(.lunch)

    XCTAssertTrue(model.isEnteringLunch, "lunch should be open")
    XCTAssertFalse(model.isEnteringSnooze, "snooze should be closed")
    XCTAssertFalse(model.isEnteringMeeting, "meeting should be closed")
  }

  /// beginEntry(_:) ensures mutual exclusion when opening snooze.
  func testBeginEntrySnoozeClosesOtherEntries() {
    let model = WindowModel()
    model.isEnteringLunch = true
    model.isEnteringMeeting = true

    model.beginEntry(.snooze)

    XCTAssertTrue(model.isEnteringSnooze, "snooze should be open")
    XCTAssertFalse(model.isEnteringLunch, "lunch should be closed")
    XCTAssertFalse(model.isEnteringMeeting, "meeting should be closed")
  }

  /// beginEntry(_:) ensures mutual exclusion when opening meeting.
  func testBeginEntryMeetingClosesOtherEntries() {
    let model = WindowModel()
    model.isEnteringSnooze = true
    model.isEnteringLunch = true

    model.beginEntry(.meeting)

    XCTAssertTrue(model.isEnteringMeeting, "meeting should be open")
    XCTAssertFalse(model.isEnteringSnooze, "snooze should be closed")
    XCTAssertFalse(model.isEnteringLunch, "lunch should be closed")
  }
}

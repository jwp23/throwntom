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
    XCTAssertTrue(model.dismiss())
    XCTAssertFalse(model.showsShortcuts)
    XCTAssertEqual(model.panel, .stats)
    XCTAssertTrue(model.dismiss())
    XCTAssertNil(model.panel)
    XCTAssertFalse(model.dismiss(), "nothing left to close")
  }

  /// Escape answers the duration field before the sheet or the panel, so it always closes
  /// whatever the user is actually looking at.
  func testDismissClosesTheSnoozeFieldBeforeEverythingElse() {
    let model = WindowModel()
    model.panel = .tasks
    model.showsShortcuts = true
    model.isEnteringSnooze = true

    XCTAssertTrue(model.dismiss())
    XCTAssertFalse(model.isEnteringSnooze)
    XCTAssertTrue(model.showsShortcuts, "the sheet should still be open")
    XCTAssertEqual(model.panel, .tasks, "the panel should still be open")
  }

  func testTheSnoozeFieldStartsClosed() {
    XCTAssertFalse(WindowModel().isEnteringSnooze)
  }
}

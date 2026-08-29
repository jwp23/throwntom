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
}

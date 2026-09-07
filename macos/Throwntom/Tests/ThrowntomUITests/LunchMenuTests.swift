import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// The lengths behind the Timer menu's "Lunch" submenu (`AppMenus.lunchMenu`), which offers the
/// same choices as the chip's own pull-down.
final class LunchMenuTests: XCTestCase {

  func testTheMenuOffersThirtyAndSixtyMinutesThenACustomLength() {
    let menu = MenuModel.lunch(canStart: true)
    XCTAssertEqual(menu.items.map(\.action), [.start(minutes: 30), .start(minutes: 60), .custom])
    XCTAssertEqual(menu.items.map(\.title), ["30 minutes", "1 hour", "Custom…"])
  }

  /// There is no way out here, unlike the meeting and snooze pickers — Skip is already that —
  /// so the whole menu is one group.
  func testEveryChoiceIsOneGroup() {
    let menu = MenuModel.lunch(canStart: true)
    XCTAssertEqual(menu.groups.count, 1)
  }

  func testTheChoicesFollowWhetherLunchCanStart() {
    XCTAssertTrue(MenuModel.lunch(canStart: true).items.allSatisfy(\.isEnabled))
    XCTAssertTrue(MenuModel.lunch(canStart: false).items.allSatisfy { !$0.isEnabled })
  }

  func testNoLunchItemBindsAKey() {
    XCTAssertTrue(MenuModel.lunch(canStart: true).items.allSatisfy { $0.shortcut == nil })
  }

}

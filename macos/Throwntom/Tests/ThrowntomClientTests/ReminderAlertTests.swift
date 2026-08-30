import Foundation
import UserNotifications
import XCTest
@testable import ThrowntomClient

final class ReminderAlertContentTests: XCTestCase {
  func testCategoryCarriesTheCycleReminderButtons() {
    let category = ReminderAlert.category

    XCTAssertEqual(category.identifier, ReminderNotification.categoryIdentifier)
    XCTAssertEqual(category.actions.map(\.identifier), ReminderNotification.cycleActions.map(\.rawValue))
    XCTAssertEqual(category.actions.map(\.title), ReminderNotification.cycleActions.map(\.title))
  }

  func testMorningCategoryCarriesTheMorningNudgeButtons() {
    let category = ReminderAlert.morningCategory

    XCTAssertEqual(category.identifier, ReminderNotification.morningCategoryIdentifier)
    XCTAssertEqual(category.actions.map(\.identifier), ReminderNotification.morningActions.map(\.rawValue))
    XCTAssertEqual(category.actions.map(\.title), ReminderNotification.morningActions.map(\.title))
  }

  func testRequestShowsTheGivenTitleAndBodyRightAway() {
    let request = ReminderAlert.request(title: "Throwntom", body: "Ready for a short break")

    XCTAssertEqual(request.identifier, ReminderNotification.requestIdentifier)
    XCTAssertEqual(request.content.title, "Throwntom")
    XCTAssertEqual(request.content.body, "Ready for a short break")
    XCTAssertEqual(request.content.categoryIdentifier, ReminderNotification.categoryIdentifier)
    XCTAssertNil(request.trigger)
  }

  func testMorningRequestUsesTheMorningCategory() {
    let request = ReminderAlert.morningRequest(title: "Throwntom", body: "Ready to start your day?")

    XCTAssertEqual(request.identifier, ReminderNotification.requestIdentifier)
    XCTAssertEqual(request.content.title, "Throwntom")
    XCTAssertEqual(request.content.body, "Ready to start your day?")
    XCTAssertEqual(request.content.categoryIdentifier, ReminderNotification.morningCategoryIdentifier)
    XCTAssertNil(request.trigger)
  }

  /// The chime is the only audio path (ADR-009). A banner sound would fire once, as the banner
  /// posts, which is the same moment the chime sounds ring one — so a banner that carried its own
  /// sound would double every reminder's first alert and add nothing to any later one.
  func testNeitherReminderCarriesABannerSound() {
    XCTAssertNil(ReminderAlert.request(title: "Throwntom", body: "Ready").content.sound)
    XCTAssertNil(ReminderAlert.morningRequest(title: "Throwntom", body: "Ready").content.sound)
  }
}

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

  /// The daemon plays nothing (ADR-003), so a reminder is heard only if its own banner sounds.
  func testBothRemindersAreAudible() {
    XCTAssertEqual(ReminderAlert.request(title: "Throwntom", body: "Ready").content.sound, .default)
    XCTAssertEqual(ReminderAlert.morningRequest(title: "Throwntom", body: "Ready").content.sound, .default)
  }
}

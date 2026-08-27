import Foundation
import UserNotifications
import XCTest
@testable import ThrowntomClient

final class ReminderAlertContentTests: XCTestCase {
    func testCategoryCarriesEveryReminderButton() {
        let category = ReminderAlert.category

        XCTAssertEqual(category.identifier, ReminderNotification.categoryIdentifier)
        XCTAssertEqual(category.actions.map(\.identifier), ReminderNotification.Action.allCases.map(\.rawValue))
        XCTAssertEqual(category.actions.map(\.title), ReminderNotification.Action.allCases.map(\.title))
    }

    func testRequestShowsTheGivenTitleAndBodyRightAway() {
        let request = ReminderAlert.request(title: "Throwntom", body: "Ready for a short break")

        XCTAssertEqual(request.identifier, ReminderNotification.requestIdentifier)
        XCTAssertEqual(request.content.title, "Throwntom")
        XCTAssertEqual(request.content.body, "Ready for a short break")
        XCTAssertEqual(request.content.categoryIdentifier, ReminderNotification.categoryIdentifier)
        XCTAssertNil(request.trigger)
    }
}

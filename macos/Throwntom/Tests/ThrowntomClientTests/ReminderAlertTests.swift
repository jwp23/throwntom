import Foundation
import UserNotifications
import XCTest
@testable import ThrowntomClient

/// A notification centre that records what throwntom-alert asked of it, and either answers at
/// once or never, so the helper's waiting and error handling can be driven without a real one.
private final class FakeNotificationCenter: ReminderAlertCenter, @unchecked Sendable {
    enum Answer {
        case immediately(Error?)
        case never
    }

    private let answer: Answer
    private let lock = NSLock()
    private var recordedCategories: [UNNotificationCategory] = []
    private var recordedPosts: [UNNotificationRequest] = []
    private var recordedWithdrawals: [String] = []

    init(answer: Answer = .immediately(nil)) {
        self.answer = answer
    }

    var categories: [UNNotificationCategory] { lock.withLock { recordedCategories } }
    var posted: [UNNotificationRequest] { lock.withLock { recordedPosts } }
    var withdrawn: [String] { lock.withLock { recordedWithdrawals } }

    func registerReminderCategory(_ category: UNNotificationCategory) {
        lock.withLock { recordedCategories.append(category) }
    }

    func post(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        lock.withLock { recordedPosts.append(request) }
        if case let .immediately(error) = answer { completion(error) }
    }

    func withdrawReminder(_ identifier: String, completion: @escaping () -> Void) {
        lock.withLock { recordedWithdrawals.append(identifier) }
        if case .immediately = answer { completion() }
    }
}

private struct CentreRefused: Error {}

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

final class ReminderAlertRunTests: XCTestCase {
    func testShowRegistersTheButtonsThenPostsTheReminder() {
        let centre = FakeNotificationCenter()

        let outcome = ReminderAlert.run(
            arguments: ["show", "--title", "Throwntom", "--body", "Ready"], on: centre)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(centre.categories.map(\.identifier), [ReminderNotification.categoryIdentifier])
        XCTAssertEqual(centre.posted.map(\.content.body), ["Ready"])
    }

    func testShowReportsWhatTheCentreRefused() {
        let centre = FakeNotificationCenter(answer: .immediately(CentreRefused()))

        let outcome = ReminderAlert.run(
            arguments: ["show", "--title", "Throwntom", "--body", "Ready"], on: centre)

        guard case let .failed(message) = outcome else { return XCTFail("expected a failure, got \(outcome)") }
        XCTAssertTrue(message.contains("post reminder"), message)
    }

    func testShowGivesUpOnACentreThatNeverAnswers() {
        let centre = FakeNotificationCenter(answer: .never)

        let outcome = ReminderAlert.run(
            arguments: ["show", "--title", "Throwntom", "--body", "Ready"],
            on: centre, timeout: .milliseconds(50))

        XCTAssertEqual(outcome, .failed("timed out posting the reminder"))
    }

    func testClearWithdrawsTheOutstandingReminder() {
        let centre = FakeNotificationCenter()

        let outcome = ReminderAlert.run(arguments: ["clear"], on: centre)

        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(centre.withdrawn, [ReminderNotification.requestIdentifier])
        XCTAssertTrue(centre.posted.isEmpty)
    }

    func testClearGivesUpOnACentreThatNeverAnswers() {
        let centre = FakeNotificationCenter(answer: .never)

        let outcome = ReminderAlert.run(arguments: ["clear"], on: centre, timeout: .milliseconds(50))

        XCTAssertEqual(outcome, .failed("timed out withdrawing the reminder"))
    }

    func testArgumentsThatAreNeitherFormAskForUsage() {
        let centre = FakeNotificationCenter()

        XCTAssertEqual(ReminderAlert.run(arguments: [], on: centre), .usage)
        XCTAssertEqual(ReminderAlert.run(arguments: ["show", "--title", "only"], on: centre), .usage)
        XCTAssertEqual(ReminderAlert.run(arguments: ["bogus"], on: centre), .usage)
        XCTAssertTrue(centre.posted.isEmpty)
        XCTAssertTrue(centre.withdrawn.isEmpty)
    }
}

import UserNotifications
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - StubAuthorizer

/// Answers the way macOS does, including the refusal it gives once a prompt has gone unanswered.
struct StubAuthorizer: NotificationAuthorizer {
  var status = UNAuthorizationStatus.notDetermined
  var granted = false
  var refusal: NSError?

  func authorizationStatus() async -> UNAuthorizationStatus {
    status
  }

  func requestAuthorization() async throws -> Bool {
    if let refusal {
      throw refusal
    }
    return granted
  }
}

/// What macOS returns from `requestAuthorization` once the prompt has been answered or abandoned:
/// UNErrorDomain code 1, with no prompt shown and no further chance to ask.
let notificationsNotAllowed = NSError(
  domain: UNErrorDomain,
  code: 1,
  userInfo: [NSLocalizedDescriptionKey: "Notifications are not allowed for this application"],
)

// MARK: - ReminderAuthorizationTests

/// What the user is told about a reminder macOS will not deliver. An unauthorized reminder is
/// accepted without complaint and simply never appears, so this text is the only trace of it.
final class ReminderAuthorizationTests: XCTestCase {
  func testAGrantedRequestLeavesNothingToReport() {
    XCTAssertEqual(ReminderAuthorization.requested(granted: true, error: nil), ReminderAuthorization())
  }

  func testARefusedRequestReportsWhatMacOSSaid() {
    let authorization = ReminderAuthorization.requested(granted: false, error: notificationsNotAllowed)

    XCTAssertEqual(
      authorization.problem,
      "Reminders will not appear: macOS would not allow them.",
    )
  }

  /// `UNUserNotificationCenter` refuses through plain `NSError`s too, and an undescribed one reads
  /// as its domain and a code. The sentence under the chips is followed by Open Notification
  /// Settings…, which is the reader's move whatever the framework called the failure.
  func testMacOSsOwnErrorTextNeverReachesTheWindow() throws {
    let undescribed = NSError(domain: "UNErrorDomain", code: 1)

    for problem in [
      ReminderAuthorization.requested(granted: false, error: undescribed).problem,
      ReminderAuthorization.rejected().problem,
    ] {
      let sentence = try XCTUnwrap(problem)
      XCTAssertFalse(sentence.contains("UNErrorDomain"), sentence)
      XCTAssertFalse(sentence.lowercased().contains("error 1"), sentence)
      XCTAssertEqual(sentence, "Reminders will not appear: macOS would not allow them.")
    }
  }

  func testDecliningThePromptIsReportedThoughMacOSRaisesNoError() {
    let authorization = ReminderAuthorization.requested(granted: false, error: nil)

    XCTAssertEqual(
      authorization.problem,
      "Reminders will not appear: notifications are turned off for Throwntom.",
    )
  }

  func testDeliverableStatusesLeaveNothingToReport() {
    XCTAssertNil(ReminderAuthorization.reported(.authorized).problem)
    XCTAssertNil(ReminderAuthorization.reported(.provisional).problem)
  }

  func testARefusalAlreadyOnRecordIsReported() {
    XCTAssertEqual(
      ReminderAuthorization.reported(.denied).problem,
      "Reminders will not appear: notifications are turned off for Throwntom.",
    )
  }

  func testNeverHavingBeenAskedIsReported() {
    XCTAssertEqual(
      ReminderAuthorization.reported(.notDetermined).problem,
      "Reminders will not appear until you allow notifications for Throwntom.",
    )
  }

  func testTheSettingsLinkAddressesTheNotificationsPane() throws {
    let url = try XCTUnwrap(ReminderResponder.notificationSettingsURL)

    XCTAssertEqual(url.scheme, "x-apple.systempreferences")
    XCTAssertEqual(
      url.absoluteString,
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
    )
  }
}

// MARK: - ReminderResponderAuthorizationTests

/// What the responder records when macOS answers, which is what the window shows.
@MainActor
final class ReminderResponderAuthorizationTests: XCTestCase {

  // MARK: Internal

  func testTheAppReportsNothingBeforeMacOSHasAnswered() throws {
    let responder = try makeResponder(StubAuthorizer())

    XCTAssertNil(responder.authorization.problem)
  }

  func testARefusedRequestIsKeptInsteadOfDiscarded() async throws {
    let responder = try makeResponder(StubAuthorizer(refusal: notificationsNotAllowed))

    await responder.requestAuthorization()

    XCTAssertEqual(
      responder.authorization.problem,
      "Reminders will not appear: macOS would not allow them.",
    )
  }

  func testAGrantedRequestLeavesTheUserNothingToFix() async throws {
    let responder = try makeResponder(StubAuthorizer(granted: true))

    await responder.requestAuthorization()

    XCTAssertNil(responder.authorization.problem)
  }

  func testRefreshingReadsWhatMacOSWillDoNow() async throws {
    let responder = try makeResponder(StubAuthorizer(status: .denied))

    await responder.refreshAuthorization()

    XCTAssertEqual(
      responder.authorization.problem,
      "Reminders will not appear: notifications are turned off for Throwntom.",
    )
  }

  func testRefreshingClearsAWarningOnceThePermissionIsGranted() async throws {
    let responder = try makeResponder(StubAuthorizer(status: .authorized, refusal: notificationsNotAllowed))
    await responder.requestAuthorization()
    XCTAssertNotNil(responder.authorization.problem)

    await responder.refreshAuthorization()

    XCTAssertNil(responder.authorization.problem)
  }

  // MARK: Private

  private func makeResponder(_ authorizer: StubAuthorizer) throws -> ReminderResponder {
    AppEnvironment(transport: try StubTransport(states: []), authorizer: authorizer).responder
  }

}

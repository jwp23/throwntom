import UserNotifications
import XCTest
@testable import ThrowntomUI

/// What the app answers when it is asked whether a reminder would be seen. Only the app's own
/// process can ask macOS that, so the report is the whole diagnostic: the settings that decide
/// whether a posted reminder is delivered and drawn, and what is delivered right now.
final class NotificationReportTests: XCTestCase {

  // MARK: Internal

  func testTheReportNamesEverySettingThatDecidesWhetherAReminderIsSeen() throws {
    let fields = try encode(makeReport())

    XCTAssertEqual(Set(fields.keys), [
      "authorization",
      "alerts",
      "sounds",
      "badges",
      "alertStyle",
      "notificationCenter",
      "scheduledSummary",
      "runningApp",
      "deliveredCount",
      "delivered",
      "findings",
    ])
    XCTAssertEqual(fields["runningApp"] as? String, "thisBundle")
    XCTAssertEqual(fields["authorization"] as? String, "authorized")
    XCTAssertEqual(fields["alerts"] as? String, "enabled")
    XCTAssertEqual(fields["sounds"] as? String, "enabled")
    XCTAssertEqual(fields["badges"] as? String, "disabled")
    XCTAssertEqual(fields["alertStyle"] as? String, "banner")
    XCTAssertEqual(fields["notificationCenter"] as? String, "enabled")
    XCTAssertEqual(fields["scheduledSummary"] as? String, "notSupported")
  }

  /// A delivered reminder is reported by the three things that answer "was it delivered, and
  /// when" — and by nothing else. The key set is the assertion that matters: a title or a body
  /// added to this report would be the user's own text (a reminder names the stage, and the app's
  /// own state names the focused task), so the report cannot be allowed to grow one.
  func testADeliveredReminderIsReportedByIdentifierCategoryAndTimeAndNothingElse() throws {
    let delivered = Date(timeIntervalSince1970: 1_756_900_000)
    let fields = try encode(makeReport(delivered: [
      NotificationReport.Delivered(
        identifier: "com.jwp23.throwntom.reminder.pending",
        category: "com.jwp23.throwntom.reminder",
        deliveredAt: delivered,
      )
    ]))

    XCTAssertEqual(fields["deliveredCount"] as? Int, 1)
    let entries = try XCTUnwrap(fields["delivered"] as? [[String: Any]])
    let entry = try XCTUnwrap(entries.first)
    XCTAssertEqual(Set(entry.keys), ["identifier", "category", "deliveredAt"])
    XCTAssertEqual(entry["identifier"] as? String, "com.jwp23.throwntom.reminder.pending")
    XCTAssertEqual(entry["category"] as? String, "com.jwp23.throwntom.reminder")
    XCTAssertEqual(ISO8601DateFormatter().date(from: entry["deliveredAt"] as? String ?? ""), delivered)
  }

  /// The same three fields, asserted where they are written rather than where the report happens
  /// to embed them: `Delivered` is encoded field by field, so its contract holds however the
  /// report around it is put together.
  func testADeliveredReminderEncodesItsThreeFieldsOnItsOwn() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(NotificationReport.Delivered(
      identifier: "com.jwp23.throwntom.reminder.pending",
      category: "com.jwp23.throwntom.reminder",
      deliveredAt: Date(timeIntervalSince1970: 1_756_900_000),
    ))

    let entry = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(entry.keys), ["identifier", "category", "deliveredAt"])
  }

  /// The other half of the same guarantee, and the half no assertion about the output can make.
  /// A field added to `Delivered` and left out of its encoder never reaches the JSON, so the key
  /// set above stays green while the title or the body it was built from sits in the type — one
  /// `try fields.encode` away from the report, and one careless line away from a log. `Delivered`
  /// is built from `UNNotificationContent`, so what it is allowed to hold is the guarantee.
  func testADeliveredReminderHoldsNothingButThoseThreeFields() {
    let fields = Mirror(reflecting: NotificationReport.Delivered(
      identifier: "com.jwp23.throwntom.reminder.pending",
      category: "com.jwp23.throwntom.reminder",
      deliveredAt: Date(timeIntervalSince1970: 1_756_900_000),
    )).children.compactMap(\.label)

    XCTAssertEqual(Set(fields), ["identifier", "category", "deliveredAt"])
  }

  func testNothingIsReportedWhenMacOSWillShowTheReminder() {
    XCTAssertEqual(makeReport().findings, [])
  }

  /// The state a dev loop lands in: the permission prompt is an ordinary banner in the corner of
  /// the screen, and quitting with it unanswered is recorded as a refusal that is never asked
  /// about again. Nothing the app does afterwards can undo it.
  func testDeniedNotificationsAreReportedAsUndoableOnlyInSystemSettings() {
    XCTAssertEqual(
      makeReport(authorization: .denied).findings,
      ["Notifications are denied for Throwntom. Only System Settings can grant them again: "
        + "macOS records a permission prompt that was never answered as a refusal."],
    )
  }

  func testNotificationsNotYetAskedAboutAreReported() {
    XCTAssertEqual(
      makeReport(authorization: .notDetermined).findings,
      ["Throwntom has not been granted notifications yet; the app asks the first time it runs."],
    )
  }

  /// The three ways a reminder is delivered and still never seen. Each is a setting the user (or
  /// a Focus mode's automation) can have changed without connecting it to the missing banner.
  func testEverySettingThatDeliversAReminderWithoutShowingItIsReported() {
    XCTAssertEqual(
      makeReport(alerts: .disabled).findings,
      ["Alerts are turned off for Throwntom, so a delivered reminder is never drawn on screen."],
    )
    XCTAssertEqual(
      makeReport(alertStyle: .none).findings,
      ["The alert style is None, so a delivered reminder is never drawn on screen."],
    )
    XCTAssertEqual(
      makeReport(scheduledSummary: .enabled).findings,
      ["Scheduled Summary is on for Throwntom, so reminders are held back for a digest."],
    )
  }

  /// Measured on macOS 26: a reminder the installed app had on screen was reported as delivered
  /// to a build with the same code signature and not to one with a different signature, which a
  /// rebuild is enough to produce. An empty list reads as "nothing was ever posted", so a report
  /// answered by a copy that did not post anything says so.
  func testAReportRunFromAnotherCopyOfTheAppSaysWhoseNotificationsItCannotSee() {
    XCTAssertEqual(
      makeReport(runningApp: .anotherBundle).findings,
      ["Throwntom is running from a different copy of the app. macOS answers each copy "
        + "about the notifications that copy posted, so the delivered list here need not be the "
        + "running app's; run this against that copy instead."],
    )
  }

  /// The plainest reason for a missing reminder: the app that posts them is not running. The
  /// daemon goes on timing without it and says nothing.
  func testAnAppThatIsNotRunningIsReportedAsPostingNothing() {
    XCTAssertEqual(
      makeReport(runningApp: .notRunning).findings,
      ["Throwntom is not running, so no reminder is being posted; the daemon goes on timing."],
    )
  }

  /// Which copy of the app is running is read from the bundles macOS has on record, so the two
  /// answers that matter — "the one asked" and "another one" — are settled here rather than by
  /// eyeballing paths.
  func testTheRunningCopyOfTheAppIsRecognisedByItsBundle() {
    let mine = URL(fileURLWithPath: "/Users/tester/Applications/Throwntom.app")
    let other = URL(fileURLWithPath: "/Users/tester/build/Throwntom.app")

    XCTAssertEqual(NotificationReport.RunningApp.of(bundle: mine, running: [other, mine]), .thisBundle)
    XCTAssertEqual(NotificationReport.RunningApp.of(bundle: mine, running: [other]), .anotherBundle)
    XCTAssertEqual(NotificationReport.RunningApp.of(bundle: mine, running: []), .notRunning)
  }

  func testTheReportIsAskedForByAFlagAndNotByTheProgramsOwnName() {
    XCTAssertTrue(NotificationReport.isRequested(["Throwntom", "--notification-report"]))
    XCTAssertFalse(NotificationReport.isRequested(["Throwntom"]))
    XCTAssertFalse(NotificationReport.isRequested(["--notification-report"]))
  }

  // MARK: Private

  /// A machine that will show the reminder, so each test names only the setting it is about.
  private func makeReport(
    authorization: UNAuthorizationStatus = .authorized,
    alerts: UNNotificationSetting = .enabled,
    alertStyle: UNAlertStyle = .banner,
    scheduledSummary: UNNotificationSetting = .notSupported,
    runningApp: NotificationReport.RunningApp = .thisBundle,
    delivered: [NotificationReport.Delivered] = [],
  ) -> NotificationReport {
    NotificationReport(
      authorization: authorization,
      alerts: alerts,
      sounds: .enabled,
      badges: .disabled,
      alertStyle: alertStyle,
      notificationCenter: .enabled,
      scheduledSummary: scheduledSummary,
      runningApp: runningApp,
      delivered: delivered,
    )
  }

  private func encode(_ report: NotificationReport) throws -> [String: Any] {
    let data = Data(try report.json().utf8)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

}

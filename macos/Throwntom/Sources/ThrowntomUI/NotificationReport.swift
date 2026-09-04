import Foundation
import UserNotifications

/// What macOS will do with a reminder right now, and what it has already delivered — the two
/// halves of "was it posted, and was it shown?".
///
/// A reminder can fail to reach the user in three different places, and they look identical from
/// outside the app: permission was never granted, the settings deliver it without drawing it, or
/// nothing was ever posted. This separates them. Only the app's own process can ask macOS any of
/// it (`SystemNotificationInspector`), so the report is a value the app writes out rather than
/// something a script can read from the outside.
///
/// It carries no notification text. A reminder's body is built from the daemon's state and can
/// name the focused task, so — as in `ClientLog.describe` — what must not be reported is dropped
/// at the boundary by shape rather than by discipline: `Delivered` has nowhere to put it.
public struct NotificationReport: Equatable, Encodable {

  // MARK: Public

  /// Which copy of Throwntom is running, and so whose reminders the delivered list can be about.
  ///
  /// macOS answers a copy of an app about the notifications that copy posted, and it tells the
  /// copies apart by their code signature: measured on macOS 26, a build whose signature differs
  /// from the running app's is answered with an empty delivered list while the reminder is on
  /// screen, and a byte-identical build at another path is answered with the reminder. An empty
  /// list is indistinguishable from a reminder that was never posted, which is the wrong answer
  /// to the only question this report exists for, so it is flagged rather than left to be read
  /// as "nothing was posted". The bundle a build sits in stands in for its signature here: a
  /// rebuild is what changes the signature, and a rebuild is what a second bundle holds.
  public enum RunningApp: String, Encodable {
    /// The app answering this report is the one that is running: it posted whatever is delivered.
    case thisBundle
    /// A different copy of Throwntom is running. Its reminders are not in this report.
    case anotherBundle
    /// No copy of Throwntom is running, so nothing is posting reminders at all.
    case notRunning

    static func of(bundle: URL, running: [URL]) -> RunningApp {
      let bundles = running.map(\.standardizedFileURL)
      if bundles.isEmpty {
        return .notRunning
      }
      return bundles.contains(bundle.standardizedFileURL) ? .thisBundle : .anotherBundle
    }
  }

  /// One reminder macOS has delivered and not yet had taken down: which reminder it was, and when
  /// it arrived. Deliberately three fields, none of them the banner's own words.
  public struct Delivered: Equatable, Encodable {

    // MARK: Public

    /// Written field by field rather than by the synthesized encoder, for the same reason the
    /// report itself is: a property nobody names here cannot reach the output. This is the type
    /// built from `UNNotificationContent`, which holds the title and the body, so it is the half
    /// that must fail closed — a field added to it stays out of the report until someone writes
    /// a line for it, instead of appearing the moment it is declared.
    public func encode(to encoder: any Encoder) throws {
      var fields = encoder.container(keyedBy: CodingKeys.self)
      try fields.encode(identifier, forKey: .identifier)
      try fields.encode(category, forKey: .category)
      try fields.encode(deliveredAt, forKey: .deliveredAt)
    }

    // MARK: Internal

    let identifier: String
    let category: String
    let deliveredAt: Date

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
      case identifier
      case category
      case deliveredAt
    }

  }

  /// The flag that asks the app for this report instead of the window. It is answered by the
  /// bundle's own executable and nothing else: macOS gives a process the notification identity of
  /// the app whose `CFBundleExecutable` it is, so a separate binary — even one inside the same
  /// bundle — is answered with a blank record instead of the app's real settings.
  public static let flag = "--notification-report"

  /// Whether this run was asked for the report. The first argument is the program's own path
  /// rather than anything the caller asked for, so it is not searched.
  public static func isRequested(_ arguments: [String]) -> Bool {
    arguments.dropFirst().contains(flag)
  }

  public func encode(to encoder: any Encoder) throws {
    var fields = encoder.container(keyedBy: CodingKeys.self)
    try fields.encode(Self.describe(authorization), forKey: .authorization)
    try fields.encode(Self.describe(alerts), forKey: .alerts)
    try fields.encode(Self.describe(sounds), forKey: .sounds)
    try fields.encode(Self.describe(badges), forKey: .badges)
    try fields.encode(Self.describe(alertStyle), forKey: .alertStyle)
    try fields.encode(Self.describe(notificationCenter), forKey: .notificationCenter)
    try fields.encode(Self.describe(scheduledSummary), forKey: .scheduledSummary)
    try fields.encode(runningApp, forKey: .runningApp)
    // The headline answer, ahead of the list it counts: a reader looking for "did anything
    // arrive?" should not have to count an array to find out.
    try fields.encode(delivered.count, forKey: .deliveredCount)
    try fields.encode(delivered, forKey: .delivered)
    try fields.encode(findings, forKey: .findings)
  }

  // MARK: Internal

  /// Whether macOS may deliver a reminder at all, and how it would show one.
  let authorization: UNAuthorizationStatus
  let alerts: UNNotificationSetting
  let sounds: UNNotificationSetting
  let badges: UNNotificationSetting

  /// Banner or Alert — or None, which delivers the reminder and draws nothing.
  let alertStyle: UNAlertStyle
  let notificationCenter: UNNotificationSetting

  /// Notification Summary: on, reminders are held back and shown together later, which for a
  /// reminder about the minute it is delivered in is the same as never arriving.
  let scheduledSummary: UNNotificationSetting

  /// Whose reminders the delivered list below is about.
  let runningApp: RunningApp

  /// The reminders macOS is holding for this app right now. Empty is not a fault: the app takes
  /// its reminder down as soon as the wait it is about is over.
  let delivered: [Delivered]

  /// Everything in the settings that would stop a posted reminder reaching the user, worded so
  /// that the sentence names what to change. Empty means macOS will show the next one — which
  /// leaves the reasons this report cannot see: a Focus mode, or a reminder that was never posted.
  var findings: [String] {
    var found = [String]()
    switch authorization {
    case .denied: found.append(Self.denied)
    case .notDetermined: found.append(Self.notAsked)
    default: break
    }
    if alerts == .disabled {
      found.append(Self.alertsOff)
    }
    if alertStyle == UNAlertStyle.none {
      found.append(Self.styleNone)
    }
    if scheduledSummary == .enabled {
      found.append(Self.summarised)
    }
    switch runningApp {
    case .anotherBundle: found.append(Self.otherCopy)
    case .notRunning: found.append(Self.notRunning)
    case .thisBundle: break
    }
    return found
  }

  func json() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(self), as: UTF8.self)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case authorization
    case alerts
    case sounds
    case badges
    case alertStyle
    case notificationCenter
    case scheduledSummary
    case runningApp
    case deliveredCount
    case delivered
    case findings
  }

  /// The state a rebuild-and-relaunch loop lands in without meaning to: macOS shows the permission
  /// prompt as an ordinary banner, and a prompt left unanswered when the app quits is recorded as
  /// a refusal. Afterwards `requestAuthorization` fails at once and a posted reminder is dropped.
  private static let denied = "Notifications are denied for Throwntom. Only System Settings can grant them again: "
    + "macOS records a permission prompt that was never answered as a refusal."
  private static let notAsked = "Throwntom has not been granted notifications yet; the app asks the first time it runs."
  private static let alertsOff = "Alerts are turned off for Throwntom, so a delivered reminder is never drawn on screen."
  private static let styleNone = "The alert style is None, so a delivered reminder is never drawn on screen."
  private static let summarised = "Scheduled Summary is on for Throwntom, so reminders are held back for a digest."

  /// The trap a rebuild lays for its own diagnosis: the build you just made answers about
  /// notifications only it posted, and it has posted none.
  private static let otherCopy = "Throwntom is running from a different copy of the app. macOS answers each copy "
    + "about the notifications that copy posted, so the delivered list here need not be the "
    + "running app's; run this against that copy instead."
  private static let notRunning = "Throwntom is not running, so no reminder is being posted; the daemon goes on timing."

  private static func describe(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "notDetermined"
    case .denied: "denied"
    case .authorized: "authorized"
    case .provisional: "provisional"
    case .ephemeral: "ephemeral"
    @unknown default: "unknown"
    }
  }

  private static func describe(_ setting: UNNotificationSetting) -> String {
    switch setting {
    case .notSupported: "notSupported"
    case .disabled: "disabled"
    case .enabled: "enabled"
    @unknown default: "unknown"
    }
  }

  private static func describe(_ style: UNAlertStyle) -> String {
    switch style {
    case .none: "none"
    case .banner: "banner"
    case .alert: "alert"
    @unknown default: "unknown"
    }
  }

}

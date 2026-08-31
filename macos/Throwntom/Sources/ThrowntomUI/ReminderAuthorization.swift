import Foundation
import UserNotifications

// MARK: - NotificationAuthorizer

/// The notification-centre answers the responder acts on, so what the app reports for each of
/// them can be worked out without the user's real notification settings, which no test process
/// may reach.
protocol NotificationAuthorizer {
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization() async throws -> Bool
}

// MARK: - ReminderAuthorization

/// What the user is told about reminders macOS will not deliver. An unauthorized reminder is
/// accepted without complaint and then never appears, so this text is its only trace: without it
/// the user hears the sound, sees no banner, and has nothing to look at.
struct ReminderAuthorization: Equatable {

  // MARK: Internal

  /// nil while reminders will arrive, which leaves the window with nothing to say.
  var problem: String?

  /// Whether a reminder posted now reaches the user: nothing to report means nothing in the way.
  var willDeliver: Bool {
    problem == nil
  }

  /// What macOS answered when asked to deliver reminders. A refusal arrives either as an error
  /// or as `granted == false`, depending on whether the prompt was answered or abandoned.
  static func requested(granted: Bool, error: Error?) -> ReminderAuthorization {
    if error != nil {
      return ReminderAuthorization(problem: refused)
    }
    return granted ? ReminderAuthorization() : ReminderAuthorization(problem: turnedOff)
  }

  /// A reminder macOS would not accept. Permission is the usual reason and only System Settings
  /// can grant it, so a refused reminder is reported where a refused request is. It takes no
  /// error: the refusal is the whole report, and the one it would be handed has no words worth
  /// showing (see `refused`).
  static func rejected() -> ReminderAuthorization {
    ReminderAuthorization(problem: refused)
  }

  /// What macOS will do with a reminder posted right now.
  static func reported(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
    switch status {
    case .authorized,
         .provisional,
         .ephemeral: return ReminderAuthorization()
    case .notDetermined: return ReminderAuthorization(problem: notAsked)
    case .denied: return ReminderAuthorization(problem: turnedOff)
    @unknown default: return ReminderAuthorization(problem: turnedOff)
    }
  }

  // MARK: Private

  private static let turnedOff = cannotAppear("notifications are turned off for Throwntom.")

  /// What a refusal from `UNUserNotificationCenter` is reported as, rather than its own words.
  /// It has none worth reading in the common case — an undescribed `UNError` is
  /// `The operation couldn’t be completed. (UNErrorDomain error 1.)` — and it needs none: every
  /// `problem` is drawn above Open Notification Settings… (`WindowNotes`), which is the reader's
  /// move whichever refusal this was. Kept apart from `turnedOff`, which asserts the specific
  /// reason the request never confirmed.
  private static let refused = cannotAppear("macOS would not allow them.")
  private static let notAsked = "Reminders will not appear until you allow notifications for Throwntom."

  private static func cannotAppear(_ reason: String) -> String {
    "Reminders will not appear: \(reason)"
  }

}

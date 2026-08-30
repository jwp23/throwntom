import Foundation
import UserNotifications

/// The reminder banners' content: each category with its own buttons, and
/// the requests the app posts to raise them.
public enum ReminderAlert {

  // MARK: Public

  /// The cycle reminder's buttons, as the category macOS attaches to the banner.
  public static var category: UNNotificationCategory {
    category(identifier: ReminderNotification.categoryIdentifier, actions: ReminderNotification.cycleActions)
  }

  /// The morning nudge's buttons, as its own category macOS attaches to the banner.
  public static var morningCategory: UNNotificationCategory {
    category(
      identifier: ReminderNotification.morningCategoryIdentifier,
      actions: ReminderNotification.morningActions,
    )
  }

  /// The cycle reminder's banner. No trigger: it shows as soon as it is posted.
  public static func request(title: String, body: String) -> UNNotificationRequest {
    request(title: title, body: body, categoryIdentifier: ReminderNotification.categoryIdentifier)
  }

  /// The morning nudge's banner. No trigger: it shows as soon as it is posted.
  public static func morningRequest(title: String, body: String) -> UNNotificationRequest {
    request(title: title, body: body, categoryIdentifier: ReminderNotification.morningCategoryIdentifier)
  }

  // MARK: Private

  private static func category(identifier: String, actions: [ReminderNotification.Action]) -> UNNotificationCategory {
    UNNotificationCategory(
      identifier: identifier,
      actions: actions.map { UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: []) },
      intentIdentifiers: [],
    )
  }

  private static func request(title: String, body: String, categoryIdentifier: String) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = categoryIdentifier
    // No sound: the chime is the only audio path (ADR-009). A banner sounds once, when it posts,
    // and the daemon's first ring lands in that same moment — so a banner sound could only
    // double ring one, never carry a repeat.
    return UNNotificationRequest(
      identifier: ReminderNotification.requestIdentifier,
      content: content,
      trigger: nil,
    )
  }

}

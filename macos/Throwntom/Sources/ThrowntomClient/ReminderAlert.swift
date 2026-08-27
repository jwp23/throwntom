import Foundation
import UserNotifications

/// The reminder banner's content: the category with its Snooze/Confirm
/// buttons, and the request the app posts to raise it.
public enum ReminderAlert {
    /// The reminder's buttons, as the category macOS attaches to the banner.
    public static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: ReminderNotification.categoryIdentifier,
            actions: ReminderNotification.Action.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [])
    }

    /// The banner itself. No trigger: it shows as soon as it is posted.
    public static func request(title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = ReminderNotification.categoryIdentifier
        return UNNotificationRequest(
            identifier: ReminderNotification.requestIdentifier, content: content, trigger: nil)
    }
}

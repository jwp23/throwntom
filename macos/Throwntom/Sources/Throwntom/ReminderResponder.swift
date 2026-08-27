import ThrowntomClient
import UserNotifications

/// Answers the reminder notification posted by throwntom-alert. macOS launches
/// Throwntom to deliver the response when the app is not already running, so
/// registering this at startup is what lets the user snooze or confirm after
/// quitting the menu bar app.
@MainActor
final class ReminderResponder: NSObject, UNUserNotificationCenterDelegate {
    private let client: DaemonClient

    init(client: DaemonClient) {
        self.client = client
        super.init()
    }

    /// Claims the delegate and asks for permission to alert. Called from the
    /// app's initialiser: a response queued by a notification-triggered launch
    /// is only delivered once a delegate is in place.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let action = ReminderNotification.action(for: response.actionIdentifier) else {
            completionHandler()
            return
        }
        Task { @MainActor in
            try? await ReminderNotification.answer(action, using: client)
            completionHandler()
        }
    }

    /// Shows the reminder even while Throwntom is frontmost; otherwise macOS
    /// suppresses the banner and hides the only buttons the user has.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

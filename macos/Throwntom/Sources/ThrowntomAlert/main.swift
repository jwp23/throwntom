import Foundation
import ThrowntomClient
import UserNotifications

// throwntom-alert posts and withdraws the pomodoro reminder on throwntomd's
// behalf. It exists because macOS grants notification identity by code signing
// identifier: this binary ships inside Throwntom.app signed as the app, while
// throwntomd is a plain Go binary signed as itself and gets nothing back from
// UNUserNotificationCenter.
//
//   throwntom-alert show --title <title> --body <body>
//   throwntom-alert clear

/// The real notification centre. Every method is a pass-through; only a signed process inside
/// the app bundle can exercise them, which is why `ReminderAlert` holds the logic instead.
struct SystemNotificationCenter: ReminderAlertCenter {
    private let center = UNUserNotificationCenter.current()

    func registerReminderCategory(_ category: UNNotificationCategory) {
        center.setNotificationCategories([category])
    }

    func post(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        center.add(request, withCompletionHandler: completion)
    }

    func withdrawReminder(_ identifier: String, completion: @escaping () -> Void) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        // Removal takes no completion handler, so wait on a request that does:
        // it cannot answer until the removals ahead of it have been processed.
        center.getDeliveredNotifications { _ in completion() }
    }
}

func complain(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

switch ReminderAlert.run(
    arguments: Array(CommandLine.arguments.dropFirst()), on: SystemNotificationCenter()) {
case .done:
    break
case .usage:
    complain("""
        usage: throwntom-alert show --title <title> --body <body>
               throwntom-alert clear

        """)
    exit(2)
case let .failed(message):
    complain("throwntom-alert: \(message)\n")
    exit(1)
}

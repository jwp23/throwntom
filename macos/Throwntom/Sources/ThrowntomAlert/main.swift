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

/// How long to wait for the notification daemon before giving up, so a wedged
/// usernoted cannot leave a helper process behind on every reminder tick.
let responseTimeout = DispatchTime.now() + .seconds(10)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("throwntom-alert: \(message)\n".utf8))
    exit(1)
}

guard let command = ReminderNotification.command(from: Array(CommandLine.arguments.dropFirst())) else {
    FileHandle.standardError.write(Data("""
        usage: throwntom-alert show --title <title> --body <body>
               throwntom-alert clear

        """.utf8))
    exit(2)
}

let center = UNUserNotificationCenter.current()
let finished = DispatchSemaphore(value: 0)

switch command {
case let .show(title, body):
    center.setNotificationCategories([
        UNNotificationCategory(
            identifier: ReminderNotification.categoryIdentifier,
            actions: ReminderNotification.Action.allCases.map {
                UNNotificationAction(identifier: $0.rawValue, title: $0.title, options: [])
            },
            intentIdentifiers: [])
    ])

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = ReminderNotification.categoryIdentifier
    let request = UNNotificationRequest(
        identifier: ReminderNotification.requestIdentifier, content: content, trigger: nil)

    var failure: Error?
    center.add(request) { error in
        failure = error
        finished.signal()
    }
    guard finished.wait(timeout: responseTimeout) == .success else {
        fail("timed out posting the reminder")
    }
    if let failure {
        fail("post reminder: \(failure)")
    }

case .clear:
    center.removePendingNotificationRequests(withIdentifiers: [ReminderNotification.requestIdentifier])
    center.removeDeliveredNotifications(withIdentifiers: [ReminderNotification.requestIdentifier])
    // Removal takes no completion handler, so wait on a request that does:
    // it cannot answer until the removals ahead of it have been processed.
    center.getDeliveredNotifications { _ in finished.signal() }
    guard finished.wait(timeout: responseTimeout) == .success else {
        fail("timed out withdrawing the reminder")
    }
}

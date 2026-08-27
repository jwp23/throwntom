import Foundation
import UserNotifications

/// The notification centre operations throwntom-alert needs. A protocol because
/// `UNUserNotificationCenter.current()` may only be reached from a process that is an app
/// bundle, which no test process is.
public protocol ReminderAlertCenter {
    func registerReminderCategory(_ category: UNNotificationCategory)
    func post(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func withdrawReminder(_ identifier: String, completion: @escaping () -> Void)
}

/// What throwntom-alert did, and so what the process should exit with.
public enum ReminderAlertOutcome: Equatable {
    case done
    /// The arguments were neither of the two forms; the helper prints its usage and exits 2.
    case usage
    case failed(String)
}

/// The reminder banner throwntom-alert raises and withdraws on throwntomd's behalf.
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

    /// Runs one throwntom-alert command, giving the centre up to `timeout` to answer so a wedged
    /// usernoted cannot leave a helper process behind on every reminder tick.
    public static func run(
        arguments: [String],
        on center: ReminderAlertCenter,
        timeout: DispatchTimeInterval = .seconds(10)
    ) -> ReminderAlertOutcome {
        guard let command = ReminderNotification.command(from: arguments) else { return .usage }
        let finished = DispatchSemaphore(value: 0)
        switch command {
        case let .show(title, body):
            center.registerReminderCategory(category)
            var refusal: Error?
            center.post(request(title: title, body: body)) { error in
                refusal = error
                finished.signal()
            }
            guard finished.wait(timeout: .now() + timeout) == .success else {
                return .failed("timed out posting the reminder")
            }
            if let refusal { return .failed("post reminder: \(refusal)") }
        case .clear:
            center.withdrawReminder(ReminderNotification.requestIdentifier) { finished.signal() }
            guard finished.wait(timeout: .now() + timeout) == .success else {
                return .failed("timed out withdrawing the reminder")
            }
        }
        return .done
    }
}

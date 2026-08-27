import Foundation
import UserNotifications

/// The notification-centre answers the responder acts on, so what the app reports for each of
/// them can be worked out without the user's real notification settings, which no test process
/// may reach.
protocol NotificationAuthorizer {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

/// The real notification centre. `UNUserNotificationCenter.current()` is reached only inside the
/// methods, so building one is harmless in a process that is not an app bundle.
struct SystemNotificationAuthorizer: NotificationAuthorizer {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

/// What the user is told about reminders macOS will not deliver. An unauthorized reminder is
/// accepted without complaint and then never appears, so this text is its only trace: without it
/// the user hears the sound, sees no banner, and has nothing to look at.
struct ReminderAuthorization: Equatable {
    /// nil while reminders will arrive, which leaves the popover with nothing to say.
    var problem: String?

    /// What macOS answered when asked to deliver reminders. A refusal arrives either as an error
    /// or as `granted == false`, depending on whether the prompt was answered or abandoned.
    static func requested(granted: Bool, error: Error?) -> ReminderAuthorization {
        if let error {
            return ReminderAuthorization(problem: "Reminders will not appear: \(error.localizedDescription)")
        }
        return granted ? ReminderAuthorization() : ReminderAuthorization(problem: turnedOff)
    }

    /// What macOS will do with a reminder posted right now.
    static func reported(_ status: UNAuthorizationStatus) -> ReminderAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral: return ReminderAuthorization()
        case .notDetermined: return ReminderAuthorization(problem: notAsked)
        default: return ReminderAuthorization(problem: turnedOff)
        }
    }

    private static let turnedOff = "Reminders will not appear: notifications are turned off for Throwntom."
    private static let notAsked = "Reminders will not appear until you allow notifications for Throwntom."
}

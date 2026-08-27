import AppKit
import ThrowntomClient
import UserNotifications

/// Answers the reminder notification posted by throwntom-alert. macOS launches
/// Throwntom to deliver the response when the app is not already running, so
/// registering this at startup is what lets the user snooze or confirm after
/// quitting the menu bar app.
@Observable @MainActor
final class ReminderResponder: NSObject, UNUserNotificationCenterDelegate {
    private let client: DaemonClient
    private let authorizer: NotificationAuthorizer

    /// What the popover says about reminders macOS will not deliver. Silent until macOS answers.
    private(set) var authorization = ReminderAuthorization()

    init(client: DaemonClient, authorizer: NotificationAuthorizer = SystemNotificationAuthorizer()) {
        self.client = client
        self.authorizer = authorizer
        super.init()
    }

    /// How the reminder is shown while Throwntom is frontmost; otherwise macOS
    /// suppresses the banner and hides the only buttons the user has.
    nonisolated static var presentationOptions: UNNotificationPresentationOptions { [.banner, .list] }

    /// System Settings › Notifications, the only place a refusal can be undone.
    nonisolated static let notificationSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

    /// Claims the delegate and asks for permission to alert. Called from the
    /// app's initialiser: a response queued by a notification-triggered launch
    /// is only delivered once a delegate is in place.
    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await requestAuthorization() }
    }

    /// Asks macOS to deliver reminders and keeps what it said. macOS shows the prompt as an
    /// ordinary banner in the corner of the screen, which a menu bar app has nothing else to
    /// draw the eye to; a prompt that is never answered is recorded as a refusal and is never
    /// raised again. Keeping the answer is what turns that dead end into something the user can
    /// see and undo.
    func requestAuthorization() async {
        do {
            let granted = try await authorizer.requestAuthorization()
            authorization = .requested(granted: granted, error: nil)
        } catch {
            authorization = .requested(granted: false, error: error)
        }
    }

    /// Re-reads what macOS will do with a reminder now, so permission granted in System Settings
    /// clears the warning without a relaunch.
    func refreshAuthorization() async {
        authorization = .reported(await authorizer.authorizationStatus())
    }

    /// Opens where the refusal is undone. Nothing the app can do grants the permission back.
    func openNotificationSettings() {
        guard let url = Self.notificationSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Sends the daemon the command behind a reminder button, then reports back to macOS.
    /// Identifiers that name no button of ours — a plain click, a dismissal — still report
    /// back: macOS keeps the process alive until the handler runs.
    nonisolated func respond(to actionIdentifier: String, then completion: @escaping () -> Void) {
        guard let action = ReminderNotification.action(for: actionIdentifier) else {
            completion()
            return
        }
        Task { @MainActor in
            try? await ReminderNotification.answer(action, using: client)
            completion()
        }
    }

    nonisolated func userNotificationCenter(_ _: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        respond(to: response.actionIdentifier, then: completionHandler)
    }

    nonisolated func userNotificationCenter(_ _: UNUserNotificationCenter,
                                            willPresent _: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.presentationOptions)
    }
}

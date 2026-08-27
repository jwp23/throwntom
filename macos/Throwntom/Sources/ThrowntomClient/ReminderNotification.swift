import Foundation

/// The actionable reminder throwntomd raises while the menu bar app may not be
/// running. throwntomd cannot post it itself: macOS grants notification identity
/// only to code signed with the app's bundle identifier, so the daemon shells out
/// to the throwntom-alert helper. Whichever process macOS hands the user's answer
/// to reads its buttons from here, so both answer the same way.
public enum ReminderNotification {
    public static let categoryIdentifier = "com.jwp23.throwntom.reminder"

    /// One reminder is outstanding at a time, so reusing this identifier means a
    /// new reminder replaces the previous banner instead of stacking on it.
    public static let requestIdentifier = "com.jwp23.throwntom.reminder.pending"

    /// A button on the reminder, identified by the string macOS round-trips.
    public enum Action: String, CaseIterable, Sendable {
        case snooze = "com.jwp23.throwntom.reminder.snooze"
        case confirm = "com.jwp23.throwntom.reminder.confirm"

        public var title: String {
            switch self {
            case .snooze: return TimerAction.snooze.title
            case .confirm: return TimerAction.confirm.title
            }
        }
    }

    /// nil for the responses macOS raises that are not one of our buttons, such
    /// as a plain click or a dismissal.
    public static func action(for identifier: String) -> Action? {
        Action(rawValue: identifier)
    }

    /// Sends the daemon the command behind an action.
    @MainActor
    public static func answer(_ action: Action, using client: DaemonClient) async throws {
        switch action {
        case .snooze: try await client.snooze(minutes: TimerActions.defaultSnoozeMinutes)
        case .confirm: try await client.timer(.confirm)
        }
    }

    /// What throwntom-alert was asked to do.
    public enum Command: Equatable, Sendable {
        case show(title: String, body: String)
        case clear
    }

    /// Parses throwntom-alert's arguments, excluding the executable name. The
    /// notifier in internal/notifier builds exactly these two forms.
    public static func command(from arguments: [String]) -> Command? {
        switch arguments.first {
        case "clear":
            return arguments.count == 1 ? .clear : nil
        case "show":
            return showCommand(from: Array(arguments.dropFirst()))
        default:
            return nil
        }
    }

    private static func showCommand(from flags: [String]) -> Command? {
        var title: String?
        var body: String?
        var rest = flags[...]
        while let flag = rest.popFirst() {
            guard let value = rest.popFirst() else { return nil }
            switch flag {
            case "--title": title = value
            case "--body": body = value
            default: return nil
            }
        }
        guard let title, let body else { return nil }
        return .show(title: title, body: body)
    }
}

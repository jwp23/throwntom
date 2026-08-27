import Foundation

/// The reminder notification's identifiers and buttons, and how a button
/// answers the daemon. The app posts the notification itself and reads the
/// user's answer from the identifiers defined here.
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
}

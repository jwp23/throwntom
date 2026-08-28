import Foundation

/// The reminder notification's identifiers and buttons, and how a button
/// answers the daemon. The app posts the notification itself and reads the
/// user's answer from the identifiers defined here.
public enum ReminderNotification {
  /// A button on the reminder, identified by the string macOS round-trips.
  public enum Action: String, CaseIterable, Sendable {
    case snooze = "com.jwp23.throwntom.reminder.snooze"
    case confirm = "com.jwp23.throwntom.reminder.confirm"
    case start = "com.jwp23.throwntom.reminder.start"
    case skipToday = "com.jwp23.throwntom.reminder.skip-today"

    public var title: String {
      switch self {
      case .snooze: TimerAction.snooze.title
      case .confirm: TimerAction.confirm.title
      case .start: TimerAction.start.title
      case .skipToday: TimerAction.skipToday.title
      }
    }
  }

  public static let categoryIdentifier = "com.jwp23.throwntom.reminder"

  /// The morning nudge's own category: its own action set (Start now / Snooze / Skip today)
  /// rather than the cycle reminder's Snooze/Confirm.
  public static let morningCategoryIdentifier = "com.jwp23.throwntom.reminder.morning"

  /// One reminder is outstanding at a time, so reusing this identifier means a
  /// new reminder replaces the previous banner instead of stacking on it.
  public static let requestIdentifier = "com.jwp23.throwntom.reminder.pending"

  /// The cycle reminder's buttons: confirm the next stage, or snooze it.
  public static let cycleActions: [Action] = [.snooze, .confirm]

  /// The morning nudge's buttons: start the day, snooze, or skip it entirely.
  public static let morningActions: [Action] = [.start, .snooze, .skipToday]

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
    case .start: try await client.timer(.start)
    case .skipToday: try await client.timer(.skipToday)
    }
  }
}

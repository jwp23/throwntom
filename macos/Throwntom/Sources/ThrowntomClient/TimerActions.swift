import Foundation

// MARK: - TimerVerb

/// Path segment of POST /v1/timer/{verb}.
public enum TimerVerb: String, Sendable {
  case start
  case confirm
  case pause
  case resume
  case skipToday = "skip-today"
  case newCycle = "new-cycle"
}

// MARK: - TimerAction

/// Timer verbs as the user sees them: title, shortcut hint and the daemon verb behind each.
public enum TimerAction: CaseIterable, Sendable {
  case start
  case confirm
  case pause
  case resume
  case snooze
  case skipToday
  case newCycle

  // MARK: Public

  public var title: String {
    switch self {
    case .start: "Start"
    case .confirm: "Confirm"
    case .pause: "Pause"
    case .resume: "Resume"
    case .snooze: "Snooze \(TimerActions.defaultSnoozeMinutes) min"
    case .skipToday: "Done for Today"
    case .newCycle: "New Cycle"
    }
  }

  /// Display-only hint; the real key bindings are attached to menu items in the app target.
  public var shortcutHint: String {
    switch self {
    case .start: "⌘R"
    case .confirm: "⏎"
    case .pause,
         .resume: "⌘P"
    case .snooze: "⌘⇧S"
    case .skipToday,
         .newCycle: ""
    }
  }

  /// Tooltip text: the title, and the shortcut in parentheses when the action has one.
  public var helpText: String {
    if shortcutHint.isEmpty {
      title
    } else {
      "\(title) (\(shortcutHint))"
    }
  }

  /// nil for snooze, which posts to /v1/timer/snooze with a minutes body instead.
  public var verb: TimerVerb? {
    switch self {
    case .start: .start
    case .confirm: .confirm
    case .pause: .pause
    case .resume: .resume
    case .skipToday: .skipToday
    case .newCycle: .newCycle
    case .snooze: nil
    }
  }
}

// MARK: - TimerActions

public enum TimerActions {
  public static let defaultSnoozeMinutes = 10

  /// Verbs the daemon would accept in this state, in display order. Mirrors internal/core/commands.go.
  ///
  /// Ending the day comes last in every state rather than only while idle: `handleSkipToday` has
  /// no state guard, and a user who is finished mid-pomodoro needs to be able to say so without
  /// first pausing or waiting out the phase.
  public static func available(for state: DaemonState) -> [TimerAction] {
    switch state.state {
    case .idle:
      if state.morningPending {
        [.start, .newCycle, .snooze, .skipToday]
      } else {
        [.start, .newCycle, .skipToday]
      }

    case .work,
         .shortBreak,
         .longBreak:
      [.pause, .skipToday]

    case .paused:
      [.resume, .skipToday]

    case .awaitingConfirm:
      [.confirm, .snooze, .newCycle, .skipToday]
    }
  }

  /// The single play/pause control: resuming is only on offer while the timer is paused.
  public static func pauseOrResume(for phase: DaemonState.Phase?) -> TimerAction {
    if phase == .paused {
      .resume
    } else {
      .pause
    }
  }
}

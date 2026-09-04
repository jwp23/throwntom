/// Timer verbs as the user sees them: title, shortcut hint and the daemon verb behind each.
public enum TimerAction: CaseIterable, Sendable {
  case start
  case confirm
  case pause
  case resume
  case skip
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
    case .skip: "Skip"
    case .snooze: "Snooze \(TimerActions.defaultSnoozeMinutes) min"
    case .skipToday: "Done for Today"
    case .newCycle: "New Cycle"
    }
  }

  /// Display-only hint; the real key bindings are attached to menu items in the app target.
  ///
  /// Confirm and Pause carry a shift the other verbs do not, because the unshifted keys are the
  /// platform's: ⌘P prints in every app the user has, and bare Return is what a default button and
  /// a text field commit on. `MenuBindingTests` holds the list to the platform's keys as well as to
  /// its own.
  public var shortcutHint: String {
    switch self {
    case .start: "⌘R"
    case .confirm: "⇧⏎"
    case .pause,
         .resume: "⌘⇧P"
    case .skip: "⌘K"
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
    case .skip: .skip
    case .skipToday: .skipToday
    case .newCycle: .newCycle
    case .snooze: nil
    }
  }
}

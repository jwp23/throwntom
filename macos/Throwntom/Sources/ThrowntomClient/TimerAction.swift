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
  case lunch
  case meeting

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
    case .lunch: "Lunch"
    case .meeting: "Meeting"
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
         .newCycle,
         .lunch,
         .meeting: ""
    }
  }

  /// When this verb is on offer, in words, for a cheat sheet that lists it whether or not it can
  /// fire this second. The sheet dims what is unavailable, and a dim on its own says only "not
  /// now"; this says when, so the row still teaches on the screen the reader happens to be on.
  ///
  /// It states the timer's condition and not the service's. Every verb here is a command line for
  /// the daemon, so every one of them also needs a timer service, and repeating that on every row
  /// would bury the part that differs between them.
  ///
  /// Pause and Resume are one row, one key and two faces (`TimerActions.pauseOrResume`), so the
  /// wording covers both: running is what Pause wants and paused is what Resume wants.
  /// `ShortcutConditionTests` holds each of these against `TimerActions.available(for:)`.
  public var availability: String {
    switch self {
    case .start: "while idle"
    case .confirm: "when a phase has ended"
    case .pause,
         .resume: "while a phase is running or paused"
    case .skip: "while a phase is running"
    case .snooze: "while a reminder is waiting"
    case .skipToday,
         .newCycle,
         .lunch: ""
    // A meeting can be started in any state, so there is no condition to state.
    case .meeting: ""
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

  /// nil for the two actions that carry a length — snooze and meeting — each of which posts a
  /// minutes body to a route of its own instead of taking a bare verb path.
  public var verb: TimerVerb? {
    switch self {
    case .start: .start
    case .confirm: .confirm
    case .pause: .pause
    case .resume: .resume
    case .skip: .skip
    case .skipToday: .skipToday
    case .newCycle: .newCycle
    case .lunch: .lunch
    case .snooze,
         .meeting: nil
    }
  }
}

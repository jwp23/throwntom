import Foundation

// MARK: - SnoozeAction

/// The whole snooze lifecycle as one set of verbs: defer the reminder for a while, type a
/// duration of your own, or end the deferral now. They live together because the control the
/// user reaches for is one control — a snooze that cannot be undone is half a feature.
public enum SnoozeAction: Hashable, Sendable {
  /// Suppress the outstanding reminder for this many minutes.
  case snooze(minutes: Int)
  /// Ask for a duration the presets do not cover.
  case custom
  /// End the snooze now. The reminder was only silenced, never answered, so it comes straight
  /// back — which is what makes this the inverse of `snooze` rather than a second way to dismiss.
  case cancel

  // MARK: Public

  public var title: String {
    switch self {
    case .snooze(let minutes): Minutes.title(minutes)
    case .custom: "Custom…"
    case .cancel: "Cancel Snooze"
    }
  }

  /// What the daemon should be asked, or nil for the one verb that asks the user instead.
  /// Callers have to answer `.custom` themselves; there is nothing to send until they do.
  public var request: SnoozeRequest? {
    switch self {
    case .snooze(let minutes): .snooze(minutes: minutes)
    case .cancel: .cancel
    case .custom: nil
    }
  }
}

// MARK: - SnoozeRequest

/// The snooze verbs the daemon can actually be asked for. Separate from `SnoozeAction` so
/// `Custom…` — which is a question for the user, not a command — is not expressible here and
/// cannot be dispatched into silence.
public enum SnoozeRequest: Hashable, Sendable {
  case snooze(minutes: Int)
  case cancel
}

// MARK: - SnoozeActions

public enum SnoozeActions {
  /// The durations the menu offers outright. Anything else is typed through `.custom`.
  public static let presets = [10, 15, 30, 60]

  /// What a snooze with no duration named means: the chip's plain click, the ⌘⇧S key and the
  /// notification's Snooze button all take this one.
  public static let defaultMinutes = TimerActions.defaultSnoozeMinutes

  /// The menu in order: the presets, then a way to type any other duration, then the undo.
  public static let all: [SnoozeAction] = presets.map { .snooze(minutes: $0) } + [.custom, .cancel]
}

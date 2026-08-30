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
    case .snooze(let minutes): Self.durationTitle(minutes)
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

  // MARK: Private

  /// Whole hours read as hours; everything else reads as minutes. "60 minutes" is a duration
  /// nobody says out loud, and the presets are chosen so this is the only case that arises.
  private static func durationTitle(_ minutes: Int) -> String {
    if minutes >= 60, minutes % 60 == 0 {
      let hours = minutes / 60
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
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

// MARK: - SnoozeDraft

/// A typed custom duration, before it is a duration. Kept apart from the text field so the
/// rules about what counts as a duration are testable without a view.
public enum SnoozeDraft {

  /// The longest snooze worth accepting. The daemon would take any positive number of minutes,
  /// but past a full day the entry is far likelier to be a typo than an intention, and a snooze
  /// nobody meant is invisible until the reminder fails to arrive.
  public static let maximumMinutes = 1440

  /// The minutes a typed entry asks for, or nil when it asks for nothing usable. Deliberately
  /// strict: only a whole number of minutes, so "10m" and "1.5" are refused rather than guessed at.
  public static func minutes(from text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed) else { return nil }
    guard value > 0, value <= maximumMinutes else { return nil }
    return value
  }

}

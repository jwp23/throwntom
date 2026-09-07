import Foundation

// MARK: - LunchAction

/// The lengths the lunch picker offers, mirroring the meeting picker: two presets and a way to
/// type a length neither covers. Unlike meeting there is no `.end` here — lunch is already
/// exitable through the Skip chip (`TimerActions.available(for:)`), so a second way out would be
/// two chips for one outcome.
public enum LunchAction: Hashable, Sendable {
  /// Go to lunch for this many minutes.
  case start(minutes: Int)
  /// Ask for a length the presets do not cover.
  case custom

  // MARK: Public

  public var title: String {
    switch self {
    case .start(let minutes): Minutes.title(minutes)
    case .custom: "Custom…"
    }
  }

  /// What the daemon should be asked, or nil for the one verb that asks the user instead.
  /// Callers have to answer `.custom` themselves; there is nothing to send until they do.
  public var request: LunchRequest? {
    switch self {
    case .start(let minutes): .start(minutes: minutes)
    case .custom: nil
    }
  }
}

// MARK: - LunchRequest

/// The lunch verbs the daemon can actually be asked for, carrying an explicit length. Separate
/// from `LunchAction` so `Custom…` — a question for the user, not a command — is not expressible
/// here and cannot be dispatched into silence.
///
/// A plain click has no request of its own: it sends the bare `lunch` verb with no body, and the
/// daemon answers with today's configured length (`DaemonClient.perform(TimerAction)`). Only the
/// picker's explicit choices post a length here.
public enum LunchRequest: Hashable, Sendable {
  case start(minutes: Int)
}

// MARK: - LunchActions

public enum LunchActions {
  /// The lengths the menu offers outright. Two, matching the meeting picker; anything else is
  /// typed through `.custom`.
  public static let presets = [30, 60]

  /// The menu in order: the lengths, then a way to type any other.
  public static let all: [LunchAction] = presets.map { .start(minutes: $0) } + [.custom]
}

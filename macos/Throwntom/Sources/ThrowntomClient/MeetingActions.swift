import Foundation

// MARK: - MeetingAction

/// The whole meeting lifecycle as one set of verbs: go into a meeting for a while, type a length
/// of your own, or come out of one now. They live together for the reason the snooze verbs do —
/// the control the user reaches for is one control, and a meeting that cannot be ended early is
/// half a feature, since a meeting finishing early is the ordinary case rather than the odd one.
public enum MeetingAction: Hashable, Sendable {
  /// Go into a meeting of this many minutes.
  case start(minutes: Int)
  /// Ask for a length the presets do not cover.
  case custom
  /// Come out of the meeting now. The time spent in it is still credited, so this ends the phase
  /// rather than discarding it — which is what separates it from skipping a pomodoro.
  case end

  // MARK: Public

  public var title: String {
    switch self {
    case .start(let minutes): Minutes.title(minutes)
    case .custom: "Custom…"
    case .end: "End Meeting"
    }
  }

  /// What the daemon should be asked, or nil for the one verb that asks the user instead.
  /// Callers have to answer `.custom` themselves; there is nothing to send until they do.
  public var request: MeetingRequest? {
    switch self {
    case .start(let minutes): .start(minutes: minutes)
    case .end: .end
    case .custom: nil
    }
  }
}

// MARK: - MeetingRequest

/// The meeting verbs the daemon can actually be asked for. Separate from `MeetingAction` so
/// `Custom…` — a question for the user, not a command — is not expressible here and cannot be
/// dispatched into silence.
public enum MeetingRequest: Hashable, Sendable {
  case start(minutes: Int)
  case end
}

// MARK: - MeetingActions

public enum MeetingActions {
  /// The lengths the menu offers outright. Two, because these are the two lengths a calendar
  /// actually books; anything else is typed through `.custom`.
  public static let presets = [30, 60]

  /// What a meeting with no length named means: the chip's plain click takes this one. It is the
  /// shorter preset deliberately — a meeting that runs long is ended by the user noticing, while
  /// one that ends early costs nothing, and the credit follows the time actually spent either way.
  public static let defaultMinutes = 30

  /// The menu in order: the lengths, then a way to type any other, then the way out.
  public static let all: [MeetingAction] = presets.map { .start(minutes: $0) } + [.custom, .end]
}

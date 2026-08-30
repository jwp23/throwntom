import Foundation

/// The daemon's DaemonState document (GET /v1/state and every SSE frame).
public struct DaemonState: Codable, Equatable, Sendable {
  public enum Phase: String, Codable, Sendable {
    case idle
    case work
    case shortBreak = "short_break"
    case longBreak = "long_break"
    case awaitingConfirm = "awaiting_confirm"
    case paused

    /// How the phase is named in the window.
    public var displayName: String {
      switch self {
      case .idle: "Idle"
      case .work: "Pomodoro"
      case .shortBreak: "Short break"
      case .longBreak: "Long break"
      case .awaitingConfirm: "Confirm"
      case .paused: "Paused"
      }
    }
  }

  public struct NextStage: Codable, Equatable, Sendable {
    public init(state: Phase, duration: Int) {
      self.state = state
      self.duration = duration
    }

    public var state: Phase
    /// Seconds.
    public var duration: Int

    /// One-line preview of the upcoming stage, e.g. "Pomodoro 25 min". Minutes truncate.
    public var summary: String {
      "\(state.displayName) \(duration / 60) min"
    }
  }

  public var state: Phase
  public var phaseEndAt: Date?
  /// Seconds left when paused.
  public var pausedRemaining: Int
  /// The phase a pause interrupted; `.idle` whenever the timer is not paused.
  public var pausedFrom: Phase
  public var completedToday: Int
  public var workSessionsInBlock: Int
  public var longBreakEvery: Int
  public var nextStage: NextStage?
  public var morningPending: Bool
  public var snoozeUntil: Date?
  public var statusLine: String
  public var focusedTaskIds: [Int]
  /// How many chimes the outstanding reminder has asked for, resetting when it is retired.
  /// The daemon plays no sound of its own (ADR-007), so the client sounds the repeat by
  /// watching this climb.
  public var reminderRings: Int
  /// Whether the user has ended the work day. The timer is idle either way, so this is the only
  /// thing that tells an idle timer waiting to be started from one that is done until tomorrow.
  public var dayEnded: Bool
}

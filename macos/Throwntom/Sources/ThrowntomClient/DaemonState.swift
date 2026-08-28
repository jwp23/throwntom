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

    /// How the phase is named in the menu bar app.
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
  public var completedToday: Int
  public var workSessionsInBlock: Int
  public var longBreakEvery: Int
  public var nextStage: NextStage?
  public var morningPending: Bool
  public var snoozeUntil: Date?
  public var statusLine: String
  public var focusedTaskIds: [Int]
}

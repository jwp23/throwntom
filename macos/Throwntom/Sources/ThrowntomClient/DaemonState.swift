import Foundation

/// The daemon's DaemonState document (GET /v1/state and every SSE frame).
public struct DaemonState: Codable, Equatable, Sendable {
  public enum Phase: String, Codable, Sendable {
    case idle
    case work
    case shortBreak = "short_break"
    case longBreak = "long_break"
    /// The break the user chooses rather than earns. No transition leads to it; only the `lunch`
    /// verb does (`internal/engine/engine.go`).
    case lunch
    case awaitingConfirm = "awaiting_confirm"
    case paused

    // MARK: Public

    /// How the phase is named in the window.
    public var displayName: String {
      switch self {
      case .idle: "Idle"
      case .work: "Pomodoro"
      case .shortBreak: "Short break"
      case .longBreak: "Long break"
      case .lunch: "Lunch"
      case .awaitingConfirm: "Confirm"
      case .paused: "Paused"
      }
    }
  }

  /// A phase the timer could move into, and how long it would run for. Mirrors `core.Stage`
  /// (`internal/core/state.go`), which serves both `next_stage` and `owed_stage`.
  public struct Stage: Codable, Equatable, Sendable {
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
  /// What confirm would move on to, so it is present only while a finished phase waits to be
  /// confirmed.
  public var nextStage: Stage?
  /// What start would enter, so it is present only while the timer is idle. Stop is a suspend, so
  /// an idle timer can owe the break it earned, and without this a client shows Idle beside a
  /// Start control and cannot say which phase pressing it begins. Mutually exclusive with
  /// `nextStage` by construction in the daemon.
  public var owedStage: Stage?
  public var morningPending: Bool
  public var snoozeUntil: Date?
  /// The daemon's own rendering of the current state, the string the TUI shows. The window
  /// composes its own text from the fields above instead, so nothing in this client reads it. It
  /// stays because it is part of the daemon's state document, and `StateDecodingTests` pins that
  /// it still decodes — not because anything here is waiting to use it.
  public var statusLine: String
  public var focusedTaskIds: [Int]
  /// How many chimes the outstanding reminder has asked for, resetting when it is retired.
  /// The daemon plays no sound of its own (ADR-007), so the client sounds the repeat by
  /// watching this climb.
  public var reminderRings: Int
  /// Whether the user has ended the work day. The timer is idle either way, so this is the only
  /// thing that tells an idle timer waiting to be started from one that is done until tomorrow.
  public var dayEnded: Bool
  /// The user's `float_window_when_waiting` setting, passed straight through by the daemon. It
  /// decides nothing there: what a client does with its window is the client's (ADR-003), and the
  /// setting rides state only because the config file it is written in is the daemon's.
  public var floatWindowWhenWaiting: Bool
  /// Whether the pause in flight has outlasted `paused_too_long_minutes`. The daemon keeps that
  /// clock and says only that the pause has been forgotten; what to do about it is the client's
  /// (ADR-003), and here it is a Dock bounce. False whenever the timer is not paused.
  public var pausedTooLong: Bool
  /// The user's `bounce_dock_when_paused` setting, passed straight through by the daemon the way
  /// `floatWindowWhenWaiting` is. The daemon publishes `pausedTooLong` on the same clock either
  /// way; only whether this app bounces the Dock over it depends on this (ADR-003).
  public var bounceDockWhenPaused: Bool
}

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
            case .idle: return "Idle"
            case .work: return "Pomodoro"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            case .awaitingConfirm: return "Confirm"
            case .paused: return "Paused"
            }
        }
    }

    public struct NextStage: Codable, Equatable, Sendable {
        public var state: Phase
        /// Seconds.
        public var duration: Int

        public init(state: Phase, duration: Int) {
            self.state = state
            self.duration = duration
        }

        /// One-line preview of the upcoming stage, e.g. "Pomodoro 25 min". Minutes truncate.
        public var summary: String { "\(state.displayName) \(duration / 60) min" }
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

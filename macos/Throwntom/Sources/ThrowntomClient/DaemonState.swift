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
    }

    public struct NextStage: Codable, Equatable, Sendable {
        public var state: Phase
        /// Seconds.
        public var duration: Int

        public init(state: Phase, duration: Int) {
            self.state = state
            self.duration = duration
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

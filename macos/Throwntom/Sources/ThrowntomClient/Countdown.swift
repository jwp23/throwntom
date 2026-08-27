import Foundation

/// Local 1 Hz ticking of the daemon's status line. The daemon owns the wording; the app only refreshes MM:SS.
public enum Countdown {
    private static let runningPhases: Set<DaemonState.Phase> = [.work, .shortBreak, .longBreak]
    private static let clock = #/\d{2,}:\d{2}/#

    public static func tickedStatusLine(_ state: DaemonState, now: Date) -> String {
        guard runningPhases.contains(state.state), let end = state.phaseEndAt else { return state.statusLine }
        let line = state.statusLine
        guard let match = line.firstMatch(of: clock) else { return line }
        return line.replacingCharacters(in: match.range, with: formatRemaining(end.timeIntervalSince(now)))
    }

    /// Same output as Go's formatRemaining: floor to seconds, clamp at zero, MM:SS with minutes unbounded.
    public static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

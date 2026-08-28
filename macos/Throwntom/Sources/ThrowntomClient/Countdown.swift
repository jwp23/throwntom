import Foundation

/// Local 1 Hz ticking of the daemon's status line. The daemon owns the wording; the app only refreshes MM:SS.
public enum Countdown {

  // MARK: Public

  public static func tickedStatusLine(_ state: DaemonState, now: Date) -> String {
    guard runningPhases.contains(state.state), let end = state.phaseEndAt else { return state.statusLine }
    let line = state.statusLine
    guard let match = line.firstMatch(of: clock) else { return line }
    return line.replacingCharacters(in: match.range, with: formatRemaining(end.timeIntervalSince(now)))
  }

  /// Same output as Go's formatRemaining: floor to seconds, clamp at zero, MM:SS with minutes unbounded.
  /// Pinned to en_US_POSIX so the separator stays ":" (what `clock` matches above) regardless of
  /// the user's system locale.
  public static func formatRemaining(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return Duration.seconds(total).formatted(
      .time(pattern: .minuteSecond(padMinuteToLength: 2)).locale(Self.posixLocale)
    )
  }

  // MARK: Private

  private static let runningPhases: Set<DaemonState.Phase> = [.work, .shortBreak, .longBreak]
  private static let clock = #/\d{2,}:\d{2}/#
  private static let posixLocale = Locale(identifier: "en_US_POSIX")

}

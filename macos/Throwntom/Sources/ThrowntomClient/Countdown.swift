import Foundation

/// Formats the countdown the window draws. `Ticker` owns the 1 Hz re-render; this only turns a
/// remaining interval into MM:SS, which is what lets the countdown advance between daemon updates
/// rather than on daemon traffic.
public enum Countdown {

  // MARK: Public

  /// Same output as Go's formatRemaining (`internal/pomodoro/timer.go`, `%02d:%02d`): floor to
  /// seconds, clamp at zero, MM:SS with minutes unbounded.
  /// Pinned to en_US_POSIX so the separator stays ":" regardless of the user's system locale. The
  /// TUI renders the same remaining time in Go, where it is never localized, and the two surfaces
  /// can be open side by side; a client that drifted to a comma would disagree with the other one
  /// about the same timer.
  public static func formatRemaining(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return Duration.seconds(total).formatted(
      .time(pattern: .minuteSecond(padMinuteToLength: 2)).locale(Self.posixLocale)
    )
  }

  // MARK: Private

  private static let posixLocale = Locale(identifier: "en_US_POSIX")

}

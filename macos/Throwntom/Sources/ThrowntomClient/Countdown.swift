import Foundation

/// Local 1 Hz ticking of the countdown the window draws, off `Ticker`, so MM:SS advances between
/// daemon updates rather than on daemon traffic.
public enum Countdown {

  // MARK: Public

  /// Same output as Go's formatRemaining (`internal/pomodoro/timer.go`, `%02d:%02d`): floor to
  /// seconds, clamp at zero, MM:SS with minutes unbounded.
  /// Pinned to en_US_POSIX so the separator stays ":" regardless of the user's system locale. The
  /// daemon formats its own copy of this string in Go, which is never localized, and a client that
  /// drifted to a comma would disagree with the daemon about the same remaining time.
  public static func formatRemaining(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return Duration.seconds(total).formatted(
      .time(pattern: .minuteSecond(padMinuteToLength: 2)).locale(Self.posixLocale)
    )
  }

  // MARK: Private

  private static let posixLocale = Locale(identifier: "en_US_POSIX")

}

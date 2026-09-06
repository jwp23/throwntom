import Foundation

/// Formats the times the window draws: how long is left, and the hour something comes back at.
/// `Ticker` owns the 1 Hz re-render, so both advance between daemon updates rather than on daemon
/// traffic.
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

  /// The hour on a wall clock, in the reader's own 12- or 24-hour convention. The opposite case
  /// from `formatRemaining`: minutes left are the same number everywhere and are pinned to POSIX,
  /// while an hour is read against a clock on the wall and a calendar on the screen, both of which
  /// are the reader's. The locale and zone are arguments so a test can name them; the window passes
  /// the user's.
  public static func formatTimeOfDay(
    _ date: Date,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent,
  ) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened)
    style.locale = locale
    style.timeZone = timeZone
    return date.formatted(style)
  }

  // MARK: Private

  private static let posixLocale = Locale(identifier: "en_US_POSIX")

}

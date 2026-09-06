import XCTest
@testable import ThrowntomClient

final class CountdownTests: XCTestCase {

  func testFormatRemainingMatchesGo() {
    XCTAssertEqual(Countdown.formatRemaining(0), "00:00")
    XCTAssertEqual(Countdown.formatRemaining(-3), "00:00")
    XCTAssertEqual(Countdown.formatRemaining(59.9), "00:59")
    XCTAssertEqual(Countdown.formatRemaining(1500), "25:00")
    XCTAssertEqual(Countdown.formatRemaining(6000), "100:00")
  }

  /// The TUI renders the same remaining time in Go, where it is never localized, so a
  /// locale-sensitive formatter here would disagree with it. `fi_FI` is known to use a period for
  /// this pattern, so it would catch a regression back to the unlocalized `Duration.TimeFormatStyle`.
  func testFormatRemainingStaysColonSeparatedRegardlessOfSystemLocale() {
    let fi = Duration.seconds(754).formatted(
      .time(pattern: .minuteSecond(padMinuteToLength: 2)).locale(Locale(identifier: "fi_FI"))
    )
    XCTAssertFalse(fi.contains(":"), "fi_FI is expected to use a non-colon separator here")
    XCTAssertEqual(Countdown.formatRemaining(754), "12:34")
  }

  /// The hour a snooze comes back at is the opposite case from the countdown above: a countdown is
  /// the same everywhere and is pinned to POSIX, while an hour is read against a wall clock and a
  /// calendar, so it has to arrive in the reader's own 12- or 24-hour convention. Asserted around
  /// the separator rather than on the whole string, because the space before `PM` is a narrow
  /// no-break space in current Foundation and a plain one in older versions.
  func testTimeOfDayFollowsTheReadersOwnClockConvention() throws {
    let evening = Date(timeIntervalSince1970: 1_787_677_200)
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))

    let twelveHour = Countdown.formatTimeOfDay(evening, locale: Locale(identifier: "en_US"), timeZone: utc)
    XCTAssertTrue(twelveHour.hasPrefix("5:00"), twelveHour)
    XCTAssertTrue(twelveHour.contains("PM"), twelveHour)
    XCTAssertEqual(Countdown.formatTimeOfDay(evening, locale: Locale(identifier: "en_GB"), timeZone: utc), "17:00")
  }

  /// The zone is the reader's too: a deadline the daemon sent as an instant has to be named in the
  /// hours the reader's own clock shows, not in UTC.
  func testTimeOfDayIsNamedInTheGivenZone() throws {
    let evening = Date(timeIntervalSince1970: 1_787_677_200)
    let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))

    XCTAssertEqual(Countdown.formatTimeOfDay(evening, locale: Locale(identifier: "en_GB"), timeZone: tokyo), "2:00")
  }

}

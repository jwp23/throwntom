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

}

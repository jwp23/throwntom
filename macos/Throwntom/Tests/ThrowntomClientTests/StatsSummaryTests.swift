import XCTest
@testable import ThrowntomClient

final class StatsSummaryTests: XCTestCase {

  // MARK: Internal

  func testDecodesGoFieldNames() throws {
    let s = try DaemonJSON.goFieldDecoder.decode(StatsSummary.self, from: body)
    XCTAssertEqual(s.today, .init(pomodoros: 7, focusMinutes: 175, pauses: 1, snoozes: 0))
    XCTAssertEqual(s.allTime.pomodoros, 412)
    XCTAssertEqual(s.streaks, .init(current: 5, longest: 12))
    XCTAssertEqual(s.patterns, .init(bestDay: 2, bestHour: 9, snoozeRate: 0.1, pauseRate: 0.2))
  }

  func testRowsInDisplayOrder() throws {
    let s = try DaemonJSON.goFieldDecoder.decode(StatsSummary.self, from: body)
    XCTAssertEqual(StatsRows.rows(s), [
      .init(label: "Today", value: "7 · 2h 55m"),
      .init(label: "This week", value: "23 · 9h 35m"),
      .init(label: "This month", value: "61 · 25h"),
      .init(label: "All time", value: "412 · 171h"),
      .init(label: "Streak", value: "5 days (best 12)"),
      .init(label: "Best hour", value: "9:00–10:00"),
    ])
  }

  func testDurationFormatMatchesTUI() {
    XCTAssertEqual(StatsRows.formatDuration(minutes: 0), "0m")
    XCTAssertEqual(StatsRows.formatDuration(minutes: 59), "59m")
    XCTAssertEqual(StatsRows.formatDuration(minutes: 60), "1h")
    XCTAssertEqual(StatsRows.formatDuration(minutes: 125), "2h 5m")
  }

  func testStreakOfOneIsSingular() {
    let s = StatsSummary(
      today: .init(pomodoros: 0, focusMinutes: 0, pauses: 0, snoozes: 0),
      thisWeek: .init(
        pomodoros: 0,
        focusMinutes: 0,
        pauses: 0,
        snoozes: 0,
      ),
      thisMonth: .init(pomodoros: 0, focusMinutes: 0, pauses: 0, snoozes: 0),
      allTime: .init(
        pomodoros: 0,
        focusMinutes: 0,
        pauses: 0,
        snoozes: 0,
      ),
      streaks: .init(current: 1, longest: 1),
      patterns: .init(bestDay: 0, bestHour: 23, snoozeRate: 0, pauseRate: 0),
    )
    XCTAssertEqual(StatsRows.rows(s)[4].value, "1 day (best 1)")
    XCTAssertEqual(StatsRows.rows(s)[5].value, "23:00–24:00")
  }

  // MARK: Private

  /// Shape of the body as `internal/daemon/routes.go:92-99` writes it: Go field names, no tags.
  private let body = Data("""
    {"Today":{"Pomodoros":7,"FocusMinutes":175,"Pauses":1,"Snoozes":0,"DailyCounts":null},
     "ThisWeek":{"Pomodoros":23,"FocusMinutes":575,"Pauses":3,"Snoozes":1,
       "DailyCounts":[{"Date":"2026-08-24T00:00:00-07:00","Count":4},{"Date":"2026-08-25T00:00:00-07:00","Count":6}]},
     "ThisMonth":{"Pomodoros":61,"FocusMinutes":1500,"Pauses":9,"Snoozes":2,"DailyCounts":null},
     "AllTime":{"Pomodoros":412,"FocusMinutes":10260,"Pauses":40,"Snoozes":11,"DailyCounts":null},
     "Streaks":{"Current":5,"Longest":12},
     "Patterns":{"BestDay":2,"BestHour":9,"AvgByWeekday":[0,1.5,2,1,0.5,0,0],"SnoozeRate":0.1,"PauseRate":0.2}}
    """.utf8)

}

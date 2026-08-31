import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class StatsPanelTests: XCTestCase {

  // MARK: Internal

  func testLoaderProducesRows() async throws {
    let transport = try StubTransport(states: [])
    transport.statsBody = body
    let environment = AppEnvironment(transport: transport)
    let loader = StatsLoader()
    XCTAssertEqual(loader.outcome, .loading)
    await loader.load(from: environment.client)
    XCTAssertEqual(loader.outcome, .loaded([
      .init(label: "Today", value: "7 · 2h 55m"),
      .init(label: "This week", value: "23 · 9h 35m"),
      .init(label: "This month", value: "61 · 25h"),
      .init(label: "All time", value: "412 · 171h"),
      .init(label: "Streak", value: "5 days (best 12)"),
      .init(label: "Best hour", value: "9:00–10:00"),
    ]))
  }

  func testLoaderReportsAFailureAsASentence() async {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let loader = StatsLoader()
    await loader.load(from: environment.client)
    guard case .failed(let message) = loader.outcome else { return XCTFail("expected failure, got \(loader.outcome)") }
    XCTAssertTrue(message.hasPrefix("Stats unavailable: "), message)
    // The panel must borrow the client's wording rather than describe the Error itself, so a
    // failed fetch reads like every other failure in the window (throwntom-6dl).
    XCTAssertEqual(message, "Stats unavailable: " + DaemonError.transport("no daemon").userMessage)
  }

  /// The transport's own words — `transport("no daemon")`, a URLSession domain, an errno — are what
  /// interpolating the raw `Error` used to put on a phase-coloured window.
  func testLoaderNeverShowsTheErrorsOwnDescription() async {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport(message: "connect(2) ENOENT"))
    let loader = StatsLoader()
    await loader.load(from: environment.client)
    guard case .failed(let message) = loader.outcome else { return XCTFail("expected failure, got \(loader.outcome)") }
    XCTAssertFalse(message.contains("connect(2)"), message)
    XCTAssertFalse(message.contains("transport("), message)
  }

  func testTheValueColumnSaysWhatItCounts() {
    XCTAssertEqual(StatsRows.unitsHeader, "Pomodoros · focus time")
  }

  func testTheLegendDefinesStreakAndBestHour() {
    let legend = StatsRows.legend
    XCTAssertTrue(legend.contains("Streak"), legend)
    XCTAssertTrue(legend.contains("Best hour"), legend)
    // The two terms the numbers alone cannot explain; the wording tracks internal/analytics.
    XCTAssertTrue(legend.contains("in a row"), legend)
    XCTAssertTrue(legend.contains("hour of day"), legend)
  }

  func testPanelBodyBuilds() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    _ = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work)).body
  }

  // MARK: Private

  private let body = Data("""
    {"Today":{"Pomodoros":7,"FocusMinutes":175,"Pauses":0,"Snoozes":0,"DailyCounts":null},
     "ThisWeek":{"Pomodoros":23,"FocusMinutes":575,"Pauses":0,"Snoozes":0,"DailyCounts":null},
     "ThisMonth":{"Pomodoros":61,"FocusMinutes":1500,"Pauses":0,"Snoozes":0,"DailyCounts":null},
     "AllTime":{"Pomodoros":412,"FocusMinutes":10260,"Pauses":0,"Snoozes":0,"DailyCounts":null},
     "Streaks":{"Current":5,"Longest":12},
     "Patterns":{"BestDay":2,"BestHour":9,"AvgByWeekday":[0,0,0,0,0,0,0],"SnoozeRate":0,"PauseRate":0}}
    """.utf8)

}

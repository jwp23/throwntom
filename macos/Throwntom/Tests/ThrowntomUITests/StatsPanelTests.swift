import SwiftUI
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

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed. A `switch`
  /// in a `ViewBuilder` becomes nested `_ConditionalContent`, so the generic parameters for the
  /// `.loaded` and `.failed` branches are part of `body`'s static type whether or not the panel's
  /// loader has reached that case yet — `loader` is `@State`-owned and unreachable from outside
  /// the view, but the type this reads is fixed by the source, not by which branch ran. A
  /// statement that stops being built anywhere in the switch, or the whole `VStack`/modifier chain
  /// being dropped, changes this string. StatsPanel.swift:48:5/49:7/57:9/58:9/59:11/60:13/61:15/
  /// 62:15/66:9.
  func testBodyIsBuiltFromTheHeaderSwitchAndFrame() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    XCTAssertEqual(
      shape(of: panel.body),
      "ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<VStack<TupleView<("
        + "ModifiedContent<Text, _EnvironmentKeyWritingModifier<Optional<Text.Case>>>, _ConditionalContent<"
        + "_ConditionalContent<ModifiedContent<ModifiedContent<ProgressView<EmptyView, EmptyView>, "
        + "_EnvironmentKeyWritingModifier<ControlSize>>, AccessibilityAttachmentModifier>, TupleView<(Text, "
        + "Grid<ForEach<Array<StatsRows.Row>, String, GridRow<TupleView<(Text, Text)>>>>, ModifiedContent<"
        + "Text, _FixedSizeLayout>)>>, ModifiedContent<Text, _FixedSizeLayout>>)>>, _PaddingLayout>, "
        + "_FlexFrameLayout>, _ForegroundStyleModifier<Color>>, "
        + "_InsettableBackgroundShapeModifier<Color, RoundedRectangle>>, _TaskModifier2>",
    )
  }

  /// The legend wraps within whatever width the panel is given rather than spilling past it: a
  /// render proposed a width narrower than the legend's one-line length still reports back close
  /// to that width, because `fixedSize(horizontal: false, ...)` lets it wrap instead of demanding
  /// its own ideal (single-line) width. StatsPanel.swift:66:69.
  func testTheLegendWrapsWithinTheGivenWidthInsteadOfSpillingPastIt() async throws {
    let transport = try StubTransport(states: [])
    transport.statsBody = body
    let environment = AppEnvironment(transport: transport)
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 150, height: nil))

    XCTAssertLessThan(size.width, 300, "the legend demanded its own width instead of wrapping to fit")
  }

  /// The legend grows to fit its wrapped lines rather than being clipped to whatever height the
  /// panel is offered: proposing a height far shorter than the wrapped legend needs still reports
  /// back a taller render, because `fixedSize(..., vertical: true)` refuses the offered height.
  /// StatsPanel.swift:66:86.
  func testTheLegendGrowsToFitInsteadOfBeingClippedToTheOfferedHeight() async throws {
    let transport = try StubTransport(states: [])
    transport.statsBody = body
    let environment = AppEnvironment(transport: transport)
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 150, height: 40))

    XCTAssertGreaterThan(size.height, 200, "the legend was clipped to the offered height instead of growing to fit")
  }

  /// The failure sentence wraps within whatever width the panel is given, the same as the legend
  /// does. StatsPanel.swift:69:60.
  func testTheFailureMessageWrapsWithinTheGivenWidthInsteadOfSpillingPastIt() async throws {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 60, height: 40))

    XCTAssertLessThan(size.width, 150, "the failure message demanded its own width instead of wrapping to fit")
  }

  /// The failure sentence grows to fit rather than being clipped to the offered height, the same
  /// as the legend does. StatsPanel.swift:69:77.
  func testTheFailureMessageGrowsToFitInsteadOfBeingClippedToTheOfferedHeight() async throws {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 60, height: 40))

    XCTAssertGreaterThan(size.height, 80, "the failure message was clipped to the offered height instead of growing to fit")
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

  /// Renders `view` (which must eventually settle once its `.task` completes) and waits for the
  /// render to move away from its first — `.loading` — size and then hold steady for two
  /// consecutive polls, so this returns the settled size rather than a `.loading` placeholder or a
  /// size caught mid-transition. Bounded by `timeout`, per this repo's rule against unbounded
  /// waits in a killing test.
  @MainActor
  private func renderedSize(
    _ view: some View,
    proposing proposedSize: ProposedViewSize,
    timeout: Double = 5,
  ) async throws -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.proposedSize = proposedSize
    let initial = renderer.nsImage?.size
    let deadline = Date().addingTimeInterval(timeout)
    var previous: CGSize?
    while Date() < deadline {
      try await Task.sleep(for: .milliseconds(20))
      let current = renderer.nsImage?.size
      if current != initial, current == previous {
        return try XCTUnwrap(current)
      }
      previous = current
    }
    throw TimeoutError()
  }

}

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
  /// its own ideal (single-line) width. The height floor pins this to the `.loaded` branch: the
  /// `.failed` branch's one-sentence render never clears it (measured 63pt at this same
  /// proposal), so a future bug that renders the wrong `switch` case can't pass this test on a
  /// borrowed, coincidentally-narrow width. StatsPanel.swift:66:69.
  func testTheLegendWrapsWithinTheGivenWidthInsteadOfSpillingPastIt() async throws {
    let transport = try StubTransport(states: [])
    transport.statsBody = body
    let environment = AppEnvironment(transport: transport)
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 150, height: nil))

    XCTAssertGreaterThan(size.height, Self.loadedBranchHeightFloor, "this rendered the .failed branch, not .loaded")
    XCTAssertLessThan(size.width, 300, "the legend demanded its own width instead of wrapping to fit")
  }

  /// The legend grows past a squeeze rather than being clipped to it, measured as how much height
  /// the squeeze actually took away from the legend's own unconstrained size — not the panel's
  /// absolute rendered height, which also grows with `StatsRows.rows`' row count and would erode
  /// an absolute threshold's headroom as rows are added. Row count moves the unconstrained and
  /// squeezed renders by the same amount (the header and grid are unaffected by this mutant), so
  /// their difference isolates the legend's own compression regardless of how many rows exist.
  /// The height floor on the squeezed render pins this to the `.loaded` branch, the same way the
  /// width test above does. StatsPanel.swift:66:86.
  func testTheLegendGrowsToFitInsteadOfBeingClippedToTheOfferedHeight() async throws {
    let transport = try StubTransport(states: [])
    transport.statsBody = body
    let environment = AppEnvironment(transport: transport)
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let unconstrained = try await renderedSize(panel, proposing: ProposedViewSize(width: 150, height: nil))
    let squeezed = try await renderedSize(panel, proposing: ProposedViewSize(width: 150, height: 40))

    XCTAssertGreaterThan(squeezed.height, Self.loadedBranchHeightFloor, "this rendered the .failed branch, not .loaded")
    XCTAssertLessThan(
      unconstrained.height - squeezed.height,
      130,
      "the legend was clipped to the offered height instead of growing past it",
    )
  }

  /// The failure sentence wraps within whatever width the panel is given, the same as the legend
  /// does. The height ceiling pins this to the `.failed` branch: the `.loaded` branch's grid at
  /// this same narrow proposal renders far past it (measured 529pt, against a 115pt `.failed`
  /// baseline), and the width alone can't tell the branches apart here — both report the same
  /// proposed width back. StatsPanel.swift:69:60.
  func testTheFailureMessageWrapsWithinTheGivenWidthInsteadOfSpillingPastIt() async throws {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 60, height: 40))

    XCTAssertLessThan(size.height, Self.failedBranchHeightCeiling, "this rendered the .loaded branch, not .failed")
    XCTAssertLessThan(size.width, 150, "the failure message demanded its own width instead of wrapping to fit")
  }

  /// The failure sentence grows to fit rather than being clipped to the offered height, the same
  /// as the legend does. The ceiling above the behavioural assertion pins this to the `.failed`
  /// branch the same way the width test above does — there's no separate dimension to check here
  /// (both branches report the same proposed width), so the two bounds together (`> 80`, `<
  /// failedBranchHeightCeiling`) box the height into a band only `.failed` can land in.
  /// StatsPanel.swift:69:77.
  func testTheFailureMessageGrowsToFitInsteadOfBeingClippedToTheOfferedHeight() async throws {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let panel = StatsPanel(client: environment.client, scheme: Palette.scheme(for: .work))

    let size = try await renderedSize(panel, proposing: ProposedViewSize(width: 60, height: 40))

    XCTAssertLessThan(size.height, Self.failedBranchHeightCeiling, "this rendered the .loaded branch, not .failed")
    XCTAssertGreaterThan(size.height, 80, "the failure message was clipped to the offered height instead of growing to fit")
  }

  // MARK: Private

  /// Below every measured `.loaded`-branch height in this file (180.5pt at worst, the legend's
  /// own squeezed render) and above every measured `.failed`-branch one (63pt at widest) at the
  /// proposals these tests use — the gap between the two branches, not either branch's own
  /// content, so it stays valid regardless of how tall either branch's content grows.
  private static let loadedBranchHeightFloor: CGFloat = 150

  /// Below the `.loaded` branch's height at the failure tests' narrow proposal (529pt, driven by
  /// the grid wrapping hard at 60pt wide) and above every measured `.failed`-branch height at that
  /// same proposal (50–115pt across this file's mutants).
  private static let failedBranchHeightCeiling: CGFloat = 200

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

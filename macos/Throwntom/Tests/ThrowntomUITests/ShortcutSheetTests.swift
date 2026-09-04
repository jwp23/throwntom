import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutSheetTests: XCTestCase {
  func testEverySectionListsOnlyItemsWithShortcuts() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let sections = ShortcutList.sections(for: environment)
    XCTAssertEqual(sections.map(\.name), ["Timer", "View", "Tasks", "App"])
    XCTAssertEqual(sections[0].entries.map(\.hint), ["⌘R", "⏎", "⌘P", "⌘K", "⌘⇧S"], "Skip Today, New Cycle and Lunch have none")
    XCTAssertEqual(sections[1].entries.map(\.hint), ["⌘T", "⌘⇧I", "⌘/"])
    XCTAssertEqual(sections[2].entries.map(\.hint), ["⌘N", "⌘⏎", "⌘⌫", "⌘F", "⌥↑", "⌥↓"])
    XCTAssertEqual(
      sections[3].entries,
      [.init(title: "Open Config File…", hint: "⌘,"), .init(title: "Quit Throwntom", hint: "⌘Q")],
    )
    XCTAssertTrue(sections.flatMap(\.entries).allSatisfy { !$0.hint.isEmpty })
  }

  func testSheetBodyBuilds() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    _ = ShortcutSheet(environment: environment).body
  }

  func testEscapeClosesTheSheet() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    environment.windowModel.showsShortcuts = true
    ShortcutSheet(environment: environment).close()
    XCTAssertFalse(environment.windowModel.showsShortcuts)
  }

  /// The sheet's own claim about itself is that it "stays the same complete list on every screen".
  /// It read the live daemon snapshot, so it did not: ⌘R was worded from `owedStage` and ⌘P from
  /// the phase, which meant the cheat sheet named a phase out of a daemon the rest of the window
  /// had already given up on — the same lie the Timer menu is held away from. A key reference is
  /// about the binding, so it is built from no state at all.
  func testTheSheetNamesNoPhaseFromTheDaemonSnapshot() async throws {
    let owing = makeState(phase: .idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    let environment = AppEnvironment(transport: try StubTransport(states: [owing]))
    defer { environment.client.stop() }
    environment.client.start()
    try await waitUntil { environment.client.state?.owedStage != nil }

    let timer = try XCTUnwrap(ShortcutList.sections(for: environment).first { $0.name == "Timer" })

    XCTAssertEqual(timer.entries.map(\.title), ["Start", "Confirm", "Pause", "Skip", "Snooze 10 min"])
  }
}

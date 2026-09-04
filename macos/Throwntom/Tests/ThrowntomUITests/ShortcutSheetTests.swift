import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutSheetTests: XCTestCase {

  // MARK: Internal

  func testEverySectionListsOnlyItemsWithShortcuts() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let sections = ShortcutList.sections(for: environment)
    XCTAssertEqual(sections.map(\.name), ["Timer", "View", "Tasks", "App"])
    XCTAssertEqual(
      sections[0].entries.map(\.hint),
      ["⌘R", "⇧⏎", "⌘⇧P", "⌘K", "⌘⇧S"],
      "Skip Today, New Cycle and Lunch have none",
    )
    XCTAssertEqual(sections[1].entries.map(\.hint), ["⌘T", "⌘⇧I", "⌘/", "⎋"])
    XCTAssertEqual(sections[2].entries.map(\.hint), ["⌘N", "⌘⏎", "⌘⌫", "⌘⇧F", "⌥↑", "⌥↓"])
    XCTAssertEqual(sections[3].entries.map(\.title), ["Open Config File…", "Quit Throwntom"])
    XCTAssertEqual(sections[3].entries.map(\.hint), ["⌘,", "⌘Q"])
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

  /// Escape is bound in the window and in this sheet and in no menu model, so the one list of what
  /// the app listens for was also the one place it never appeared (throwntom-bxd.17).
  func testEscapeIsListedThoughNoMenuBindsIt() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))

    let dismiss = try XCTUnwrap(entry(named: "Dismiss", in: ShortcutList.sections(for: environment)))

    XCTAssertEqual(dismiss.hint, "⎋")
    XCTAssertTrue(dismiss.isEnabled, "there is always something Escape does")
    XCTAssertFalse(dismiss.condition.isEmpty)
  }

  /// The sheet's own claim about itself is that it "stays the same complete list on every screen".
  /// It read the live daemon snapshot, so it did not: ⌘R was worded from `owedStage` and ⌘⇧P from
  /// the phase, which meant the cheat sheet named a phase out of a daemon the rest of the window
  /// had already given up on — the same lie the Timer menu is held away from. Enablement is read
  /// live now; the words are still built from no state at all.
  func testTheSheetNamesNoPhaseFromTheDaemonSnapshot() async throws {
    let owing = makeState(phase: .idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    let environment = try await environment(showing: owing)

    let timer = try XCTUnwrap(ShortcutList.sections(for: environment).first { $0.name == "Timer" })

    XCTAssertEqual(timer.entries.map(\.title), ["Start", "Confirm", "Pause", "Skip", "Snooze 10 min"])
  }

  /// The bead (throwntom-bxd.13): the shortcuts are state-gated, the sheet was built with
  /// `state: nil, daemonAvailable: true`, so a list of what the app *binds* read as a list of what
  /// *works now*. Mid-pomodoro, three of the five timer keys do nothing.
  func testTheSheetSaysWhichTimerKeysCanFireRightNow() async throws {
    let environment = try await environment(showing: makeState(phase: .work))

    let timer = try XCTUnwrap(ShortcutList.sections(for: environment).first { $0.name == "Timer" })

    XCTAssertEqual(
      timer.entries.map { "\($0.hint) \($0.isEnabled)" },
      ["⌘R false", "⇧⏎ false", "⌘⇧P true", "⌘K true", "⌘⇧S false"],
    )
  }

  /// The other half of the same read: an awaiting-confirm timer offers a different three, so the
  /// test above is about the phase rather than about the sheet disabling most of the list whatever
  /// it is told.
  func testTheSameSheetSaysSomethingElseInAnotherPhase() async throws {
    let environment = try await environment(showing: makeState(phase: .awaitingConfirm))

    let timer = try XCTUnwrap(ShortcutList.sections(for: environment).first { $0.name == "Timer" })

    XCTAssertEqual(
      timer.entries.map { "\($0.hint) \($0.isEnabled)" },
      ["⌘R false", "⇧⏎ true", "⌘⇧P false", "⌘K false", "⌘⇧S true"],
    )
  }

  /// The sheet is the one surface worth opening while the service is down, so it keeps every row —
  /// and now says which of them the outage has taken. The three local commands are what is left.
  func testTheSheetKeepsEveryRowWithNoServiceAndDimsWhatTheOutageTook() throws {
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      intents: MemoryServiceIntentStore(.stopped),
    )

    let sections = ShortcutList.sections(for: environment)

    XCTAssertEqual(sections.flatMap(\.entries).count, 17, "the list stays complete")
    XCTAssertEqual(
      sections.flatMap(\.entries).filter(\.isEnabled).map(\.hint),
      ["⌘/", "⎋", "⌘,", "⌘Q"],
      "only the commands that reach no daemon still work",
    )
  }

  /// Two commands are withheld by the sheet's own presence — Confirm, whose key the Done button
  /// would otherwise take, and ⌘/, which opens the thing already open. Both are read for the window
  /// behind the sheet, because the reader is about to close it and this is the only screen either
  /// row appears on.
  func testTheSheetAnswersForTheWindowBehindIt() async throws {
    let environment = try await environment(showing: makeState(phase: .awaitingConfirm))
    environment.windowModel.showsShortcuts = true

    let sections = ShortcutList.sections(for: environment)

    XCTAssertTrue(try XCTUnwrap(entry(named: "Confirm", in: sections)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(entry(named: "Keyboard Shortcuts", in: sections)).isEnabled)
  }

  /// A surface behind the sheet still counts. Leaving the duration field open and reading the sheet
  /// does not give Confirm its key back, because closing the sheet returns to the field.
  func testASurfaceOpenBehindTheSheetStillHoldsTheKey() async throws {
    let environment = try await environment(showing: makeState(phase: .awaitingConfirm))
    environment.windowModel.showsShortcuts = true
    environment.windowModel.isEnteringSnooze = true

    let sections = ShortcutList.sections(for: environment)

    XCTAssertFalse(try XCTUnwrap(entry(named: "Confirm", in: sections)).isEnabled)
  }

  /// A dim says "not now" and never says when, so each row carries the rule as well. These are the
  /// words; `ShortcutConditionTests` is what holds them to the code that decides.
  func testEveryRowSaysWhenItApplies() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))

    let sections = ShortcutList.sections(for: environment)

    XCTAssertEqual(sections[0].entries.map(\.condition), [
      "while idle",
      "when a phase has ended",
      "while a phase is running or paused",
      "while a phase is running",
      "while a reminder is waiting",
    ])
    XCTAssertEqual(sections[1].entries.map(\.condition), [
      "while the timer service is running",
      "while the timer service is running",
      "",
      "closes what is open",
    ])
    XCTAssertEqual(
      sections[2].entries.map(\.condition),
      [""] + Array(repeating: "with a task selected", count: 5),
      "New Task is the one task verb that needs no row to act on",
    )
    XCTAssertEqual(sections[3].entries.map(\.condition), ["", ""])
  }

  // MARK: Private

  /// An app that has read one frame from a live daemon, which is what puts a phase in hand for the
  /// sheet to answer from.
  private func environment(showing state: DaemonState) async throws -> AppEnvironment {
    let environment = AppEnvironment(transport: try StubTransport(states: [state]))
    addTeardownBlock { @MainActor in environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    return environment
  }

  private func entry(named title: String, in sections: [ShortcutList.Section]) -> ShortcutList.Entry? {
    sections.flatMap(\.entries).first { $0.title == title }
  }

}

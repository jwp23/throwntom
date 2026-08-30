import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeChipTests: XCTestCase {

  // MARK: Internal

  func testWithNoSnoozeTheChipOffersToStartOne() throws {
    let chip = try makeChip(snoozeUntil: nil)
    XCTAssertFalse(chip.isSnoozed)
    XCTAssertEqual(chip.title, "Snooze")
    XCTAssertEqual(chip.primaryAction, .snooze(minutes: SnoozeActions.defaultMinutes))
  }

  func testTheChipBuildsWithAndWithoutASnooze() throws {
    _ = try makeChip(snoozeUntil: nil).body
    _ = try makeChip(snoozeUntil: Date().addingTimeInterval(600)).body
  }

  /// The undo has to be where the snooze was. A user looking for the way out of a snooze reaches
  /// for the control that caused it, so the same chip cancels while one is running.
  func testWhileSnoozedTheSameChipIsTheUndo() throws {
    let chip = try makeChip(snoozeUntil: Date().addingTimeInterval(600))
    XCTAssertTrue(chip.isSnoozed)
    XCTAssertEqual(chip.title, "Cancel Snooze")
    XCTAssertEqual(chip.primaryAction, .cancel)
  }

  func testCustomOpensTheDurationFieldInsteadOfAskingTheDaemon() throws {
    let chip = try makeChip(snoozeUntil: nil)
    XCTAssertFalse(chip.model.isEnteringSnooze)
    chip.run(.custom)
    XCTAssertTrue(chip.model.isEnteringSnooze)
  }

  /// Every other verb, unlike `Custom…`, is a command line for the daemon.
  func testAnOrdinaryVerbDispatchesToTheDaemonRatherThanOpeningTheField() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    let chip = SnoozeChip(content: content, client: environment.client, model: environment.windowModel)
    chip.run(.snooze(minutes: 10))
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/snooze"])
  }

  /// `menuButton(for:)` is what `MenuGroups`' trailing closure delegates to, and the closure
  /// itself only runs through the (untestable) rendering pass — so it is built directly here.
  func testMenuButtonBuildsForAnEnabledAndADisabledItem() throws {
    let chip = try makeChip(snoozeUntil: nil)
    _ = chip.menuButton(for: MenuItem(action: .snooze(minutes: 10), shortcut: nil, isEnabled: true))
    _ = chip.menuButton(for: MenuItem(action: .cancel, shortcut: nil, isEnabled: false))
  }

  func testTheChipIsOfferedForEveryStateThatCanSnooze() {
    for phase in [DaemonState.Phase.idle, .awaitingConfirm] {
      let state = makeState(phase: phase, morningPending: true)
      XCTAssertTrue(TimerActions.available(for: state).contains(.snooze), "\(phase)")
    }
  }

  /// A snooze survives on screen because `morning_pending` and `awaiting_confirm` both outlast it
  /// on the daemon (`internal/core/core.go` derives pending from the outstanding reminder), so the
  /// chip carrying the undo is still there to be pressed.
  func testTheChipIsStillOfferedWhileTheSnoozeIsRunning() {
    let snoozed = makeState(phase: .awaitingConfirm, snoozeUntil: Date().addingTimeInterval(600))
    XCTAssertTrue(TimerActions.available(for: snoozed).contains(.snooze))
  }

  /// ⌘⇧S is bound to Snooze, not to cancelling one. Advertising it beside "Cancel Snooze" would
  /// promise a key that does the opposite of the chip it sits on — the exact mismatch
  /// `MenuBindingTests` exists to stop, which it cannot see because a chip binds nothing itself.
  func testTheChipStopsAdvertisingTheSnoozeKeyOnceItIsTheUndo() throws {
    XCTAssertEqual(try makeChip(snoozeUntil: nil).hint, "⌘⇧S")
    XCTAssertEqual(try makeChip(snoozeUntil: Date().addingTimeInterval(600)).hint, "")
  }

  // MARK: Private

  private func makeChip(snoozeUntil: Date?) throws -> SnoozeChip {
    let environment = try AppEnvironment(transport: StubTransport(states: []))
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm, snoozeUntil: snoozeUntil),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    return SnoozeChip(content: content, client: environment.client, model: environment.windowModel)
  }

}

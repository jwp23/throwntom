import SwiftUI
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

  /// throwntom-bxd.29: the chip's body has to be built from SplitChip, with the menu reaching
  /// via the trailing chevron (a plain click, not through Menu(primaryAction:)).
  func testTheChipIsBuiltFromSplitChipRatherThanPressAndHold() throws {
    let chip = try makeChip(snoozeUntil: nil)
    let bodyType = String(describing: type(of: chip.body))
    XCTAssertTrue(bodyType.contains("SplitChip"), bodyType)
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

  /// The snooze control has to be a chip first. A menu style that hands its
  /// label to AppKit gets AppKit's own tinting painted over `ChipLabel`, so the chip came out in
  /// brown text on the phase ground while every button beside it wore the fill (throwntom-bxd.2).
  ///
  /// This used to assert the two were the same picture byte for byte, but throwntom-bxd.29 gives
  /// menu chips a disclosure chevron that plain chips do not draw, so the pictures now differ on
  /// purpose. What still has to hold — and what would fail if AppKit's tinting came back — is that
  /// this chip paints in the plain chip's own fill and text colours rather than the system's.
  func testTheChipPaintsTheStylesFillAndTextColours() throws {
    let chip = try makeChip(snoozeUntil: nil)
    for appearance in AppearanceRender.appearances {
      let drawn = try AppearanceRender.bitmap(
        framed(chip.body, scheme: chip.content.scheme),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let fill = try AppearanceRender.swatch(
        chip.content.scheme.secondaryChip,
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let text = try AppearanceRender.swatch(
        chip.content.scheme.secondaryChipText,
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      XCTAssertGreaterThan(AppearanceRender.pixels(of: fill, in: drawn), 500, appearance.name)
      XCTAssertGreaterThan(AppearanceRender.pixels(of: text, in: drawn), 0, appearance.name)
    }
  }

  /// The durations and `Custom…` stay enabled whether or not a snooze is running — only `.cancel`
  /// answers for `isSnoozed` (`canDefer` is unconditionally `true`, per the doc comment on `menu`).
  func testEveryDurationStaysEnabledWhetherOrNotASnoozeIsRunning() throws {
    for snoozeUntil in [nil, Date().addingTimeInterval(600)] {
      let chip = try makeChip(snoozeUntil: snoozeUntil)
      let durations = chip.menu.items.filter { $0.action != .cancel }
      XCTAssertFalse(durations.isEmpty, "the menu needs a duration to exercise")
      XCTAssertTrue(durations.allSatisfy(\.isEnabled), "\(String(describing: snoozeUntil))")
    }
  }

  /// The wiring behind `testTheChipIsBuiltFromSplitChipRatherThanPressAndHold`: a plain click on
  /// the label region has to run `primaryAction` — cancel the running snooze — not merely
  /// `chip.run(...)` called directly.
  func testPressingTheLabelRegionRunsThePrimaryAction() async throws {
    let transport = try StubTransport(states: [makeState(phase: .awaitingConfirm, snoozeUntil: Date().addingTimeInterval(600))])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm, snoozeUntil: Date().addingTimeInterval(600)),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    let chip = SnoozeChip(content: content, client: environment.client, model: environment.windowModel)

    try splitChipPrimaryAction(chip)()

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/unsnooze"], "primaryAction is .cancel while snoozed")
  }

  /// `menuButton(for:)` (already built directly above) has to be what the chevron's `MenuGroups`
  /// actually builds for each item, not merely a method that can be called on the side.
  func testTheChevronMenuBuildsEveryItemThroughMenuButtonFor() throws {
    let chip = try makeChip(snoozeUntil: nil)
    let groups = try splitChipMenuGroups(chip)
    for item in groups.labelledItems {
      let built = try XCTUnwrap(groups.builtLabel(for: item))
      XCTAssertTrue(shape(of: built).contains("Button"), shape(of: built))
    }
  }

  /// The wiring behind `testMenuButtonBuildsForAnEnabledAndADisabledItem`: pressing the button a
  /// menu item built runs `run(item.action)`, the same dispatch a click would drive.
  func testPressingAMenuItemsButtonRunsItsAction() async throws {
    let transport = try StubTransport(states: [makeState(phase: .awaitingConfirm)])
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
    let groups = try splitChipMenuGroups(chip)

    try press(SnoozeAction.snooze(minutes: 10), in: groups)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/snooze"])
  }

  // MARK: Private

  /// The chip in its own box on the phase ground, the way the window draws the row.
  private func framed(_ view: some View, scheme: PhaseScheme) -> some View {
    AppearanceRender.onGround(view, scheme: scheme, width: 200, height: 44)
  }

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

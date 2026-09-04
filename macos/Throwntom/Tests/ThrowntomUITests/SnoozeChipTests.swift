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

  /// The snooze control is a pull-down, but it has to be a chip first. A menu style that hands its
  /// label to AppKit gets AppKit's own tinting painted over `ChipLabel`, so the chip came out in
  /// brown text on the phase ground while every button beside it wore the fill (throwntom-bxd.2).
  /// Drawn against the chip it sits next to, the two have to be the same picture — in both system
  /// appearances, because a window painted in its own palette does not change with the system's.
  func testTheChipIsDrawnExactlyLikeThePlainChipsBesideIt() throws {
    let chip = try makeChip(snoozeUntil: nil)
    let plain = Chip(title: chip.title, hint: chip.hint, isPrimary: false, scheme: chip.content.scheme) { }
    for appearance in AppearanceRender.appearances {
      let drawn = try AppearanceRender.bitmap(
        framed(chip.body, scheme: chip.content.scheme),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let reference = try AppearanceRender.bitmap(
        framed(plain, scheme: chip.content.scheme),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      // Two blank pictures are also identical, so the reference has to be shown to be a chip first.
      let fill = try AppearanceRender.swatch(
        chip.content.scheme.secondaryChip,
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      XCTAssertGreaterThan(AppearanceRender.pixels(of: fill, in: reference), 500, appearance.name)
      XCTAssertEqual(
        try AppearanceRender.png(drawn),
        try AppearanceRender.png(reference),
        appearance.name,
      )
    }
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

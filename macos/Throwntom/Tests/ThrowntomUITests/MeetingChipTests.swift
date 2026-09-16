import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class MeetingChipTests: XCTestCase {

  // MARK: Internal

  func testTheChipBuildsWithAndWithoutAMeetingRunning() throws {
    _ = try makeChip(phase: .idle).body
    _ = try makeChip(phase: .meeting).body
  }

  /// throwntom-bxd.29: the chip's body has to be built from SplitChip, with the menu reaching
  /// via the trailing chevron (a plain click, not through Menu(primaryAction:)).
  func testTheChipIsBuiltFromSplitChipRatherThanPressAndHold() throws {
    let chip = try makeChip(phase: .idle)
    let bodyType = String(describing: type(of: chip.body))
    XCTAssertTrue(bodyType.contains("SplitChip"), bodyType)
  }

  func testCustomOpensTheLengthFieldInsteadOfAskingTheDaemon() throws {
    let chip = try makeChip(phase: .idle)
    XCTAssertFalse(chip.model.isEnteringMeeting)
    chip.run(.custom)
    XCTAssertTrue(chip.model.isEnteringMeeting)
  }

  /// Every other verb, unlike `Custom…`, is a command line for the daemon.
  func testAnOrdinaryLengthDispatchesToTheDaemonRatherThanOpeningTheField() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = MeetingChip(
      content: content(phase: .idle),
      client: environment.client,
      model: environment.windowModel,
    )

    chip.run(.start(minutes: 30))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/meeting"])
    XCTAssertFalse(environment.windowModel.isEnteringMeeting)
  }

  /// Ending a meeting is the daemon's `skip`, which credits the time spent rather than
  /// discarding it (`internal/core/commands.go`).
  func testEndingAMeetingAsksForASkip() async throws {
    let transport = try StubTransport(states: [makeState(phase: .meeting)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = MeetingChip(
      content: content(phase: .meeting),
      client: environment.client,
      model: environment.windowModel,
    )

    chip.run(.end)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/skip"])
  }

  /// `menuButton(for:)` is what `MenuGroups`' trailing closure delegates to, and the closure
  /// itself only runs through the (untestable) rendering pass — so it is built directly here.
  func testMenuButtonBuildsForAnEnabledAndADisabledItem() throws {
    let chip = try makeChip(phase: .idle)
    _ = chip.menuButton(for: MenuItem(action: .start(minutes: 30), shortcut: nil, isEnabled: true))
    _ = chip.menuButton(for: MenuItem(action: .end, shortcut: nil, isEnabled: false))
  }

  /// The meeting control has to be a chip first. A menu style that hands
  /// its label to AppKit gets AppKit's own tinting painted over `ChipLabel`, which is what left
  /// the snooze chip in brown text on the phase ground while every button beside it wore the fill
  /// (throwntom-bxd.2).
  ///
  /// This used to assert the two were the same picture byte for byte, but throwntom-bxd.29 gives
  /// menu chips a disclosure chevron that plain chips do not draw, so the pictures now differ on
  /// purpose. What still has to hold — and what would fail if AppKit's tinting came back — is that
  /// this chip paints in the plain chip's own fill and text colours rather than the system's.
  func testTheChipPaintsTheStylesFillAndTextColours() throws {
    let chip = try makeChip(phase: .idle)
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

  /// The chip carries no key hint, so it must not leave room for one: a chip drawn with an empty
  /// hint has to be the same picture as one built without a hint at all.
  func testTheChipCarriesNoRoomForAKeyHint() throws {
    let chip = try makeChip(phase: .idle)
    XCTAssertTrue(TimerAction.meeting.shortcutHint.isEmpty)
    XCTAssertEqual(chip.title, "Meeting")
  }

  /// The lengths and `Custom…` stay enabled whether or not a meeting is running — only `.end`
  /// answers for `isMeeting` (`canStart` is unconditionally `true`).
  func testEveryLengthStaysEnabledWhetherOrNotAMeetingIsRunning() throws {
    for phase in [DaemonState.Phase.idle, .meeting] {
      let chip = try makeChip(phase: phase)
      let lengths = chip.menu.items.filter { $0.action != .end }
      XCTAssertFalse(lengths.isEmpty, "the menu needs a length to exercise")
      XCTAssertTrue(lengths.allSatisfy(\.isEnabled), "\(phase)")
    }
  }

  /// The wiring behind `testTheChipIsBuiltFromSplitChipRatherThanPressAndHold`: a plain click on
  /// the label region has to run `primaryAction` — start a meeting when idle, end one when
  /// running — not merely `chip.run(...)` called directly.
  func testPressingTheLabelRegionRunsThePrimaryAction() async throws {
    let transport = try StubTransport(states: [makeState(phase: .meeting)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = MeetingChip(
      content: content(phase: .meeting),
      client: environment.client,
      model: environment.windowModel,
    )

    try splitChipPrimaryAction(chip)()

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/skip"], "meeting's primaryAction is .end while it runs")
  }

  /// `menuButton(for:)` (already built directly above) has to be what the chevron's `MenuGroups`
  /// actually builds for each item, not merely a method that can be called on the side.
  func testTheChevronMenuBuildsEveryItemThroughMenuButtonFor() throws {
    let chip = try makeChip(phase: .idle)
    let groups = try splitChipMenuGroups(chip)
    for item in groups.labelledItems {
      let built = try XCTUnwrap(groups.builtLabel(for: item))
      XCTAssertTrue(shape(of: built).contains("Button"), shape(of: built))
    }
  }

  /// The wiring behind `testMenuButtonBuildsForAnEnabledAndADisabledItem`: pressing the button a
  /// menu item built runs `run(item.action)`, the same dispatch a click would drive.
  func testPressingAMenuItemsButtonRunsItsAction() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = MeetingChip(
      content: content(phase: .idle),
      client: environment.client,
      model: environment.windowModel,
    )
    let groups = try splitChipMenuGroups(chip)

    try press(MeetingAction.start(minutes: 30), in: groups)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/meeting"])
  }

  // MARK: Private

  /// The chip in its own box on the phase ground, the way the window draws the row.
  private func framed(_ view: some View, scheme: PhaseScheme) -> some View {
    AppearanceRender.onGround(view, scheme: scheme, width: 200, height: 44)
  }

  private func content(phase: DaemonState.Phase) -> MainWindowContent {
    MainWindowContent(
      state: makeState(phase: phase),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
  }

  private func makeChip(phase: DaemonState.Phase) throws -> MeetingChip {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return MeetingChip(
      content: content(phase: phase),
      client: environment.client,
      model: environment.windowModel,
    )
  }

}

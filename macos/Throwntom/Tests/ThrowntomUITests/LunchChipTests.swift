import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class LunchChipTests: XCTestCase {

  // MARK: Internal

  func testTheChipBuilds() throws {
    _ = try makeChip(phase: .idle).body
  }

  /// throwntom-bxd.29: press-and-hold reaching the menu is gone; SplitChip is what replaces
  /// it, so the chip's body has to actually be built from it rather than from
  /// Menu(primaryAction:), which is press-and-hold-only.
  func testTheChipIsBuiltFromSplitChipRatherThanPressAndHold() throws {
    let chip = try makeChip(phase: .idle)
    let bodyType = String(describing: type(of: chip.body))
    XCTAssertTrue(bodyType.contains("SplitChip"), bodyType)
  }

  func testCustomOpensTheLengthFieldInsteadOfAskingTheDaemon() throws {
    let chip = try makeChip(phase: .idle)
    XCTAssertFalse(chip.model.isEnteringLunch)
    chip.run(.custom)
    XCTAssertTrue(chip.model.isEnteringLunch)
  }

  /// Every other verb, unlike `Custom…`, is a command line for the daemon.
  func testAnOrdinaryLengthDispatchesToTheDaemonRatherThanOpeningTheField() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = LunchChip(
      content: content(phase: .idle),
      client: environment.client,
      model: environment.windowModel,
    )

    chip.run(.start(minutes: 30))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/lunch"])
    XCTAssertEqual(transport.commands.last?.body, #"{"minutes":30}"#)
    XCTAssertFalse(environment.windowModel.isEnteringLunch)
  }

  /// A plain click keeps the daemon's own answer for how long lunch runs — no body at all,
  /// rather than one of the picker's presets the user never chose.
  func testAPlainClickSendsNoExplicitLength() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let chip = LunchChip(
      content: content(phase: .idle),
      client: environment.client,
      model: environment.windowModel,
    )

    chip.run(nil)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/lunch"])
    XCTAssertEqual(transport.commands.last?.body, "")
  }

  /// `menuButton(for:)` is what `MenuGroups`' trailing closure delegates to, and the closure
  /// itself only runs through the (untestable) rendering pass — so it is built directly here.
  func testMenuButtonBuildsForAnEnabledAndADisabledItem() throws {
    let chip = try makeChip(phase: .idle)
    _ = chip.menuButton(for: MenuItem(action: .start(minutes: 30), shortcut: nil, isEnabled: true))
    _ = chip.menuButton(for: MenuItem(action: .custom, shortcut: nil, isEnabled: false))
  }

  /// The lunch control is a pull-down, but it has to be a chip first, for the same reason
  /// `MeetingChipTests` holds the meeting chip to it (throwntom-bxd.2).
  ///
  /// This used to assert the two were the same picture byte for byte, but throwntom-bxd.29 gives
  /// menu chips a disclosure chevron that plain chips do not draw, so the pictures now differ on
  /// purpose. What still has to hold — and what would fail if AppKit's tinting came back — is that
  /// this chip paints in the plain chip's own fill and text colours rather than the system's.
  func testTheChipIsDrawnExactlyLikeThePlainChipsBesideIt() throws {
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

  func testTheChipCarriesNoRoomForAKeyHint() throws {
    let chip = try makeChip(phase: .idle)
    XCTAssertTrue(TimerAction.lunch.shortcutHint.isEmpty)
    XCTAssertEqual(chip.title, "Lunch")
  }

  // MARK: Private

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

  private func makeChip(phase: DaemonState.Phase) throws -> LunchChip {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return LunchChip(
      content: content(phase: phase),
      client: environment.client,
      model: environment.windowModel,
    )
  }

}

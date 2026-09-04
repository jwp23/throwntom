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

  /// The meeting control is a pull-down, but it has to be a chip first. A menu style that hands
  /// its label to AppKit gets AppKit's own tinting painted over `ChipLabel`, which is what left
  /// the snooze chip in brown text on the phase ground while every button beside it wore the fill
  /// (throwntom-bxd.2). Drawn against the chip it sits next to, the two have to be the same
  /// picture — in both system appearances, because a window painted in its own palette does not
  /// change with the system's.
  func testTheChipIsDrawnExactlyLikeThePlainChipsBesideIt() throws {
    let chip = try makeChip(phase: .idle)
    let plain = Chip(title: chip.title, hint: "", isPrimary: false, scheme: chip.content.scheme) { }
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

  /// The chip carries no key hint, so it must not leave room for one: a chip drawn with an empty
  /// hint has to be the same picture as one built without a hint at all.
  func testTheChipCarriesNoRoomForAKeyHint() throws {
    let chip = try makeChip(phase: .idle)
    XCTAssertTrue(TimerAction.meeting.shortcutHint.isEmpty)
    XCTAssertEqual(chip.title, "Meeting")
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

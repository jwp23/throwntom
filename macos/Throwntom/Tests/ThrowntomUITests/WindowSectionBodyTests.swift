import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// These sections are pure functions of `MainWindowContent`; the decisions are tested there. What is
/// left is that each body builds for every phase and shape of content.
@MainActor
final class WindowSectionBodyTests: XCTestCase {
  func testHeaderBuildsForEveryPhase() {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused] {
      let content = MainWindowContent(
        state: makeState(phase: phase),
        connection: .connected,
        status: .running,
        tasks: TaskList(),
        error: nil,
        panel: nil,
        now: .now,
      )
      _ = TimerHeader(content: content).body
    }
    let disconnected = MainWindowContent(
      state: nil,
      connection: .connecting,
      status: .reaching,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    XCTAssertEqual(disconnected.pose, .disconnected)
    _ = TimerHeader(content: disconnected).body
  }

  func testGardenBuildsForEmptyAndBigDays() {
    _ = TomatoGardenView(garden: TomatoGarden(completedToday: 0, inBlock: 0, every: 4)).body
    _ = TomatoGardenView(garden: TomatoGarden(completedToday: 23, inBlock: 3, every: 4)).body
  }

  func testFocusAndNotesBuild() throws {
    let scheme = Palette.scheme(for: .work)
    _ = FocusSection(tasks: [], scheme: scheme).body
    _ = FocusSection(tasks: [makeTask(id: 1), makeTask(id: 2)], scheme: scheme).body
    let responder = AppEnvironment(transport: try StubTransport(states: [])).responder
    _ = WindowNotes(error: nil, notice: nil, responder: responder).body
    _ = WindowNotes(error: "socket closed", notice: "You stopped the timer service.", responder: responder).body
  }

  /// A note is the only account on screen of a refused command or a stopped service, and the focus
  /// list is the only account of what the pomodoro is for. Neither may be the smallest type in the
  /// window (throwntom-bxd.14, throwntom-bxd.15).
  func testNotesAndFocusRowsAreReadAtTheWindowsOwnTextSize() {
    XCTAssertEqual(WindowNotes.font, .body)
    XCTAssertEqual(FocusSection.font, Font.body.weight(.medium))
  }

  /// The star takes the ground's own text colour; `PaletteTests` is what holds that colour to
  /// 4.5:1 on every ground.
  func testTheFocusStarTakesTheGroundsOwnTextColour() {
    for (name, scheme) in Palette.schemes {
      XCTAssertEqual(FocusSection(tasks: [], scheme: scheme).markColor, scheme.taskMark, name)
    }
  }
}

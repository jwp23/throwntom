// Tests/ThrowntomUITests/MainWindowContentTests.swift
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

final class MainWindowContentTests: XCTestCase {

  // MARK: Internal

  func testWorkShowsCountdownGardenAndPauseChip() {
    let state = makeState(
      phase: .work,
      nextStage: .init(state: .shortBreak, duration: 300),
      phaseEndAt: now.addingTimeInterval(754),
      completedToday: 5,
      workSessionsInBlock: 1,
    )
    let c = content(state)
    XCTAssertEqual(c.scheme, Palette.scheme(for: .work))
    XCTAssertEqual(c.glyph, .emoji("🍅"))
    XCTAssertEqual(c.title, "Pomodoro")
    XCTAssertEqual(c.countdown, "12:34")
    XCTAssertEqual(c.nextStage, "Next: Short break 5 min")
    XCTAssertEqual(c.garden, TomatoGarden(completedToday: 5, inBlock: 1, every: 4))
    XCTAssertEqual(c.chips, [.pause])
    XCTAssertNil(c.primaryChip)
  }

  func testRunningPhaseWithoutEndDateHasNoCountdown() {
    XCTAssertNil(content(makeState(phase: .work, phaseEndAt: nil)).countdown)
  }

  func testPausedUsesRemainingSecondsAndPauseSymbol() {
    let c = content(makeState(phase: .paused, pausedRemaining: 61))
    XCTAssertEqual(c.glyph, .symbol("pause.fill"))
    XCTAssertEqual(c.countdown, "01:01")
    XCTAssertEqual(c.primaryChip, .resume)
  }

  func testIdleHasNoCountdownAndStartIsPrimary() {
    let c = content(makeState(phase: .idle))
    XCTAssertEqual(c.glyph, .emoji("🌱"))
    XCTAssertNil(c.countdown)
    XCTAssertEqual(c.chips, [.start, .newCycle, .skipToday])
    XCTAssertEqual(c.primaryChip, .start)
  }

  func testAwaitingConfirmPromotesConfirm() {
    let c = content(makeState(phase: .awaitingConfirm))
    XCTAssertEqual(c.glyph, .emoji("🔔"))
    XCTAssertEqual(c.title, "Confirm")
    XCTAssertEqual(c.primaryChip, .confirm)
    XCTAssertEqual(c.scheme, Palette.scheme(for: .awaitingConfirm))
  }

  func testBreakGlyphs() {
    XCTAssertEqual(content(makeState(phase: .shortBreak)).glyph, .emoji("☕"))
    XCTAssertEqual(content(makeState(phase: .longBreak)).glyph, .emoji("🌿"))
  }

  func testFocusedTasksFollowDaemonOrder() {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5), makeTask(id: 6)])
    let c = content(makeState(phase: .work, focusedTaskIds: [6, 4]), tasks: tasks)
    XCTAssertEqual(c.focused.map(\.id), [4, 6])
  }

  func testDisconnectedShowsPlaceholderAndNoGarden() {
    let c = content(nil, connection: .reconnecting(attempt: 2), error: "socket closed")
    XCTAssertEqual(c.scheme, Palette.scheme(for: nil))
    XCTAssertEqual(c.glyph, .symbol("bolt.horizontal.circle"))
    XCTAssertEqual(c.title, ConnectionStatus.placeholderText(state: nil, connection: .reconnecting(attempt: 2), now: now))
    XCTAssertNil(c.garden)
    XCTAssertEqual(c.chips, [])
    XCTAssertEqual(c.error, "socket closed")
  }

  func testStartingDaemonTitle() {
    XCTAssertEqual(content(nil, connection: .startingDaemon).title, "Starting timer…")
  }

  func testPanelIsCarriedThrough() {
    XCTAssertEqual(content(makeState(), panel: .stats).panel, .stats)
  }

  func testOnlyAwaitingConfirmPulses() {
    XCTAssertTrue(content(makeState(phase: .awaitingConfirm)).pulses)
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .paused] {
      XCTAssertFalse(content(makeState(phase: phase)).pulses, "\(phase)")
    }
    XCTAssertFalse(content(nil, connection: .connecting).pulses)
  }

  func testPoseFollowsThePhase() {
    XCTAssertEqual(content(makeState(phase: .work)).pose, .work)
    XCTAssertEqual(content(makeState(phase: .shortBreak)).pose, .shortBreak)
    XCTAssertEqual(content(makeState(phase: .longBreak)).pose, .longBreak)
    XCTAssertEqual(content(makeState(phase: .idle)).pose, .idle)
    XCTAssertEqual(content(makeState(phase: .awaitingConfirm)).pose, .awaitingConfirm)
    XCTAssertEqual(content(makeState(phase: .paused, pausedFrom: .shortBreak)).pose, MascotPose.shortBreak.paused())
    XCTAssertEqual(content(nil, connection: .connecting).pose, .disconnected)
  }

  // MARK: Private

  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func content(
    _ state: DaemonState?,
    connection: DaemonClient.Connection = .connected,
    tasks: TaskList = TaskList(),
    error: String? = nil,
    panel: WindowPanel? = nil,
  ) -> MainWindowContent {
    MainWindowContent(state: state, connection: connection, tasks: tasks, error: error, panel: panel, now: now)
  }

}

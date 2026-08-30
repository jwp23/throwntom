// Tests/ThrowntomUITests/MainWindowContentTests.swift
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - MainWindowContentTests

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
    XCTAssertEqual(c.title, "Pomodoro")
    XCTAssertEqual(c.countdown, "12:34")
    XCTAssertEqual(c.nextStage, "Next: Short break 5 min")
    XCTAssertEqual(c.garden, TomatoGarden(completedToday: 5, inBlock: 1, every: 4))
    XCTAssertEqual(c.chips, [.pause, .skip, .skipToday])
    XCTAssertNil(c.primaryChip)
  }

  func testRunningPhaseWithoutEndDateHasNoCountdown() {
    XCTAssertNil(content(makeState(phase: .work, phaseEndAt: nil)).countdown)
  }

  func testPausedUsesRemainingSeconds() {
    let c = content(makeState(phase: .paused, pausedRemaining: 61))
    XCTAssertEqual(c.countdown, "01:01")
    XCTAssertEqual(c.primaryChip, .resume)
  }

  func testIdleHasNoCountdownAndStartIsPrimary() {
    let c = content(makeState(phase: .idle))
    XCTAssertNil(c.countdown)
    XCTAssertEqual(c.chips, [.start, .newCycle, .skipToday])
    XCTAssertEqual(c.primaryChip, .start)
  }

  func testAwaitingConfirmPromotesConfirm() {
    let c = content(makeState(phase: .awaitingConfirm))
    XCTAssertEqual(c.title, "Confirm")
    XCTAssertEqual(c.primaryChip, .confirm)
    XCTAssertEqual(c.scheme, Palette.scheme(for: .awaitingConfirm))
  }

  func testFocusedTasksFollowDaemonOrder() {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5), makeTask(id: 6)])
    let c = content(makeState(phase: .work, focusedTaskIds: [6, 4]), tasks: tasks)
    XCTAssertEqual(c.focused.map(\.id), [4, 6])
  }

  func testDisconnectedShowsPlaceholderAndNoGarden() {
    let c = content(nil, connection: .reconnecting(attempt: 2), error: "socket closed")
    XCTAssertEqual(c.scheme, Palette.scheme(for: nil))
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
    registrationFailed: Bool = false,
    panel: WindowPanel? = nil,
  ) -> MainWindowContent {
    MainWindowContent(
      state: state,
      connection: connection,
      tasks: tasks,
      error: error,
      registrationFailed: registrationFailed,
      panel: panel,
      now: now,
    )
  }

}

// MARK: - EndOfDayContentTests

/// throwntom-azb: after the user ends the day the window has to say so. The daemon goes idle,
/// which on its own is indistinguishable from an idle timer waiting to be started.
extension MainWindowContentTests {
  func testAnEndedDayIsNamedRatherThanShownAsPlainIdle() {
    let ended = content(makeState(phase: .idle, dayEnded: true))
    XCTAssertEqual(ended.title, "Done for today")
    XCTAssertEqual(content(makeState(phase: .idle)).title, "Idle")
  }

  func testAnEndedDayStillOffersTheWayBackIn() {
    let ended = content(makeState(phase: .idle, dayEnded: true))
    XCTAssertEqual(ended.primaryChip, .start)
    XCTAssertEqual(ended.scheme, Palette.scheme(for: .idle))
  }

  /// A day the user ended is over only while the timer is idle; a running phase is its own answer.
  func testARunningPhaseIsNamedForThePhase() {
    XCTAssertEqual(content(makeState(phase: .work, dayEnded: true)).title, "Pomodoro")
  }
}

// MARK: - RefusedLaunchContentTests

/// throwntom-jtx: a refused launch has to say so even with a stale phase still in hand — the
/// daemon that phase came from is gone, and the title must not go on describing it.
extension MainWindowContentTests {
  func testARefusedLaunchOutranksAStaleRetainedPhase() {
    let stale = content(makeState(phase: .work), connection: .startingDaemon, registrationFailed: true)
    XCTAssertEqual(stale.title, "Timer service can’t launch")
  }
}

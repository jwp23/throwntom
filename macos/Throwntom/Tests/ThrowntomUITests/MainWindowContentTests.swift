// Tests/ThrowntomUITests/MainWindowContentTests.swift
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - MainWindowContentTests

final class MainWindowContentTests: XCTestCase {

  // MARK: Internal

  /// A snooze takes the reminder banner away (`ReminderBanner.waitingKind`), so without this the
  /// only evidence a snooze happened is a nudge that never arrives. That is how a stray click
  /// became ten silent minutes nobody could explain.
  func testAnActiveSnoozeSaysHowMuchOfItIsLeft() {
    let c = content(makeState(phase: .awaitingConfirm, snoozeUntil: now.addingTimeInterval(598)))
    XCTAssertEqual(c.snoozeNote, "Snoozed · 09:58 left")
  }

  func testNoSnoozeNoNote() {
    XCTAssertNil(content(makeState(phase: .awaitingConfirm)).snoozeNote)
  }

  func testASnoozePastItsDeadlineReadsAsNoTimeLeftRatherThanNegative() {
    let c = content(makeState(phase: .awaitingConfirm, snoozeUntil: now.addingTimeInterval(-30)))
    XCTAssertEqual(c.snoozeNote, "Snoozed · 00:00 left")
  }

  /// The whole window drops its daemon-derived presentation when the service is gone; a snooze
  /// deadline from a daemon that is no longer there is no more true than the phase was.
  func testADisconnectedWindowShowsNoSnooze() {
    let state = makeState(phase: .awaitingConfirm, snoozeUntil: now.addingTimeInterval(600))
    let c = MainWindowContent(
      state: state,
      connection: .stopped,
      tasks: TaskList(active: [], completed: []),
      error: nil,
      registrationFailed: true,
      panel: nil,
      now: now,
    )
    XCTAssertNil(c.snoozeNote)
  }

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
    XCTAssertEqual(c.title, ConnectionStatus.text(state: nil, connection: .reconnecting(attempt: 2), now: now))
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

  /// throwntom-ejk: the title alone was not enough. Every other field was still derived from the
  /// retained state, so the window kept a live phase colour, a running countdown and timer chips
  /// that dispatch to a daemon confirmed gone. The whole presentation has to snap to disconnected.
  func testARefusedLaunchSnapsTheWholeWindowToDisconnected() {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5)])
    let refused = content(
      makeState(
        phase: .work,
        nextStage: .init(state: .shortBreak, duration: 300),
        phaseEndAt: now.addingTimeInterval(754),
        completedToday: 5,
        workSessionsInBlock: 1,
        focusedTaskIds: [4],
      ),
      connection: .startingDaemon,
      tasks: tasks,
      registrationFailed: true,
    )

    XCTAssertEqual(refused.scheme, Palette.scheme(for: nil), "a phase ground says a phase is running")
    XCTAssertEqual(refused.pose, .disconnected)
    XCTAssertNil(refused.countdown, "nothing is counting down")
    XCTAssertNil(refused.nextStage, "nothing is coming next")
    XCTAssertNil(refused.garden)
    XCTAssertEqual(refused.chips, [], "timer verbs here are dead buttons")
    XCTAssertNil(refused.primaryChip)
    XCTAssertEqual(refused.focused, [], "the daemon that focused these is gone")
  }

  /// The way out, and the two halves of the sentence that explains why it is needed. The refusal
  /// note is the client's `registrationError`, carried in as `error`.
  func testARefusedLaunchShowsTheRefusalTheReasonAndStart() {
    let note = "launchd refused to start the timer service. Press Start Timer Service to try again."
    let refused = content(
      makeState(phase: .work),
      connection: .startingDaemon,
      error: note,
      registrationFailed: true,
    )

    XCTAssertEqual(refused.title, "Timer service can’t launch")
    XCTAssertEqual(refused.error, note)
    XCTAssertEqual(refused.serviceAction, .start)
  }

  /// The disconnected window is the same shell as every other — mascot, ground, chip rows — with
  /// the live state taken out of it. What it must never become is the IDLE screen: idle means the
  /// service is up and waiting for you to start a pomodoro, and its chips are live affordances.
  /// Wearing idle's clothes here would put the dead buttons back, in a costume.
  func testARefusedLaunchIsNotTheIdleScreen() {
    let refused = content(makeState(phase: .idle), connection: .startingDaemon, registrationFailed: true)
    let idle = content(makeState(phase: .idle))

    XCTAssertNotEqual(refused.scheme, idle.scheme, "the idle ground says the service is up")
    XCTAssertNotEqual(refused.pose, idle.pose)
    XCTAssertNotEqual(refused.title, idle.title)
    XCTAssertEqual(idle.chips, [.start, .newCycle, .skipToday], "idle's verbs are live affordances")
    XCTAssertEqual(refused.chips, [], "and none of them are true here")
  }

  /// throwntom-faa is the other disconnected window: the user stopped the service on purpose.
  /// Both offer Start on the same ground, so the title is what has to keep them apart.
  func testAFailedLaunchReadsDifferentlyFromAServiceTheUserStopped() {
    let refused = content(makeState(phase: .work), connection: .startingDaemon, registrationFailed: true)
    let stopped = content(nil, connection: .stopped)

    XCTAssertEqual(refused.serviceAction, stopped.serviceAction, "both offer the same way back")
    XCTAssertEqual(refused.scheme, stopped.scheme, "both are the disconnected ground")
    XCTAssertNotEqual(refused.title, stopped.title, "a failure must not read as a choice")
  }
}

// Tests/ThrowntomUITests/MainWindowContentTests.swift
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - MainWindowContentTests

final class MainWindowContentTests: XCTestCase {

  // MARK: Internal

  /// The reminder can be answered from the notification or the keyboard while the custom-duration
  /// field is open. `MainWindow` clears the flag off this condition, so what has to hold is that
  /// the condition actually goes false when the verb leaves.
  func testSnoozeLeavesTheOfferedVerbsOnceTheReminderIsAnswered() {
    XCTAssertTrue(content(makeState(phase: .awaitingConfirm)).chips.contains(.snooze))
    XCTAssertFalse(content(makeState(phase: .work)).chips.contains(.snooze))
    XCTAssertFalse(content(makeState(phase: .idle, morningPending: false)).chips.contains(.snooze))
  }

  /// A snooze takes the reminder banner away (`ReminderBanner.waitingKind`), so without this the
  /// only evidence a snooze happened is a nudge that never arrives. That is how a stray click
  /// became ten silent minutes nobody could explain.
  func testAnActiveSnoozeSaysHowMuchOfItIsLeft() {
    let c = content(makeState(phase: .awaitingConfirm, snoozeUntil: now.addingTimeInterval(598)))
    XCTAssertEqual(c.snoozeNote, "Snoozed · 09:58 left")
  }

  /// The snoozed line is the window's other live countdown, so it is split the same way the
  /// headline is: the minutes left are held apart from the wording, ready to be the element's
  /// value. Left inside the label they would rewrite the label every second.
  func testTheSnoozedLineKeepsItsMovingPartApartFromItsWording() {
    let c = content(makeState(phase: .awaitingConfirm, snoozeUntil: now.addingTimeInterval(598)))

    XCTAssertEqual(c.snoozeRemaining, "09:58")
    XCTAssertEqual(c.snoozeNote, "Snoozed · 09:58 left", "the line on screen still reads as one sentence")
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
      status: ServiceStatus.of(connection: .stopped, registrationFailed: true, startStalled: false),
      tasks: TaskList(active: [], completed: []),
      error: nil,
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

  /// Focus is no longer gated on a running pomodoro (`internal/core/tasks.go`), so a user can pick
  /// the work before starting it — and the window has to show what they picked, or an idle screen
  /// gives the choice no acknowledgement at all (throwntom-bxd.14).
  func testFocusedTasksShowWhileTheTimerIsIdle() {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5)])
    let c = content(makeState(phase: .idle, focusedTaskIds: [5]), tasks: tasks)
    XCTAssertEqual(c.focused.map(\.id), [5])
  }

  func testDisconnectedShowsPlaceholderAndNoGarden() {
    let c = content(nil, connection: .reconnecting(attempt: 2), error: "socket closed")
    XCTAssertEqual(c.scheme, Palette.scheme(for: nil))
    XCTAssertEqual(
      c.title,
      ConnectionStatus.text(connection: .reconnecting(attempt: 2), status: .reaching),
    )
    XCTAssertNil(c.garden)
    XCTAssertEqual(c.chips, [])
    XCTAssertEqual(c.error, "socket closed")
  }

  /// throwntom-7rb. While the client is re-dialling it still holds the phase, and that phase is
  /// still counting (ADR-008) — so the window goes on naming it and keeps its ground. What it must
  /// not do is read as a live connection: before this, a reconnect was byte-for-byte the connected
  /// window, and the only way to learn the daemon had gone was to wait for the retry budget to run
  /// out. The mark is on the title alone; the ground, countdown and verbs stay as they were.
  func testAReconnectHoldingAPhaseIsMarkedRatherThanReadingAsConnected() {
    let live = makeState(phase: .work, phaseEndAt: now.addingTimeInterval(600))
    let connected = content(live)
    let dialling = content(live, connection: .reconnecting(attempt: 1))

    XCTAssertEqual(connected.title, "Pomodoro")
    XCTAssertEqual(dialling.title, "Pomodoro (reconnecting)")
    XCTAssertNotEqual(connected.title, dialling.title)
    XCTAssertEqual(dialling.countdown, connected.countdown)
    XCTAssertEqual(dialling.scheme, connected.scheme)
    XCTAssertEqual(dialling.chips, connected.chips)
  }

  /// Every way of being out of touch while holding a phase is marked, not just the middle one: a
  /// launch already asked of launchd is no more connected than a plain retry.
  func testEveryDiallingConnectionMarksARetainedPhase() {
    let live = makeState(phase: .work, phaseEndAt: now.addingTimeInterval(600))
    for connection in [DaemonClient.Connection.connecting, .reconnecting(attempt: 3), .startingDaemon] {
      XCTAssertEqual(content(live, connection: connection).title, "Pomodoro (reconnecting)", "\(connection)")
    }
  }

  /// The mark goes on whatever title the window is showing, and the ended day is the one title
  /// that is not a phase name. It reads as a sentence rather than a phase, so it is worth pinning
  /// what it actually says: the day is still over and the client is still out of touch, and both
  /// halves have to survive being put together.
  func testTheEndedDayTitleIsMarkedLikeAnyOther() {
    XCTAssertEqual(
      content(makeState(phase: .idle, dayEnded: true), connection: .reconnecting(attempt: 1)).title,
      "Done for today (reconnecting)",
    )
  }

  /// The mark says the client is out of touch, so it must not appear when it is in touch. The
  /// day-ended title is checked too, because it is the one title not taken from the phase name.
  func testAConnectedWindowIsNeverMarked() {
    XCTAssertEqual(content(makeState(phase: .idle)).title, "Idle")
    XCTAssertEqual(
      content(makeState(phase: .idle, dayEnded: true)).title,
      "Done for today",
    )
  }

  /// The three settled absences own the title outright; a reconnect mark there would put a phase
  /// name on a screen that has deliberately dropped its phase.
  func testTheSettledAbsencesKeepTheirOwnTitles() {
    let live = makeState(phase: .work, phaseEndAt: now.addingTimeInterval(600))
    XCTAssertEqual(content(live, connection: .stopped).title, "Timer service stopped")
    XCTAssertEqual(
      content(live, connection: .startingDaemon, registrationFailed: true).title,
      "Timer service can\u{2019}t launch",
    )
    XCTAssertEqual(content(live, connection: .startingDaemon, startStalled: true).title, "Timer service isn\u{2019}t answering")
  }

  /// throwntom-46y. An idle timer can owe the break it earned (`internal/core/state.go`), so a
  /// bare Start does not say which phase pressing it begins.
  func testTheStartChipNamesThePhaseAnIdleStartWouldEnter() {
    let owing = makeState(phase: .idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    XCTAssertEqual(content(owing).title(for: .start), "Start Short break")
    XCTAssertEqual(content(makeState(phase: .idle)).title(for: .start), "Start")
  }

  /// Only Start is reworded; every other verb says what it always said.
  func testNoOtherVerbIsRewordedByTheOwedPhase() {
    let owing = content(makeState(phase: .idle, owedStage: DaemonState.Stage(state: .work, duration: 1500)))
    XCTAssertEqual(owing.title(for: .newCycle), TimerAction.newCycle.title)
    XCTAssertEqual(owing.title(for: .skipToday), TimerAction.skipToday.title)
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

  /// throwntom-jnv. The headline was three bare `Text` views, which VoiceOver reads as three
  /// unrelated stops with no relation between them and no clue that the middle one is a value that
  /// has already moved on. It is one element now: the phase and what follows it are the label, and
  /// the countdown is its value.
  func testTheHeadlineReadsAsOneLabelledThingWithTheCountdownAsItsValue() {
    let c = content(makeState(
      phase: .work,
      nextStage: DaemonState.Stage(state: .shortBreak, duration: 300),
      phaseEndAt: now.addingTimeInterval(1500),
    ))

    XCTAssertEqual(c.spokenHeadline, "Pomodoro. Next: Short break 5 min")
    XCTAssertEqual(c.countdown, "25:00", "the value is the countdown itself, not a second wording")
  }

  /// A VoiceOver user and a sighted user must be told the same thing, so the label is built from
  /// the strings already on screen rather than from a second copy of them. Two wordings drift.
  func testTheHeadlineLabelIsTheTitleAndTheLineUnderIt() {
    let states = [
      makeState(phase: .idle),
      makeState(phase: .idle, dayEnded: true),
      makeState(phase: .work, nextStage: DaemonState.Stage(state: .shortBreak, duration: 300)),
    ]
    var withAStageAfterIt = 0

    for state in states {
      let c = content(state)
      XCTAssertTrue(c.spokenHeadline.hasPrefix(c.title), "\"\(c.spokenHeadline)\" does not start with \"\(c.title)\"")
      guard let next = c.nextStage else { continue }
      withAStageAfterIt += 1
      XCTAssertTrue(c.spokenHeadline.hasSuffix(next), c.spokenHeadline)
    }

    // Without this the loop above would pass having skipped its second assertion entirely, which
    // is how a test comes to assert nothing while still failing when the code is reverted.
    XCTAssertEqual(withAStageAfterIt, 1, "no case exercised the half of the label that follows the title")
  }

  /// A screen with nothing counting has a title and nothing else under it, and the label must not
  /// invent punctuation for a sentence that is not there.
  func testAHeadlineWithNothingUnderItIsJustTheTitle() {
    let c = content(nil, connection: .stopped)

    XCTAssertEqual(c.spokenHeadline, c.title)
    XCTAssertNil(c.countdown)
  }

  /// The reconnect mark is part of what the window says, so it is part of what is read out. The
  /// spoken announcement is the *change*; this is the standing fact, there whenever the reader
  /// goes back to the headline (throwntom-92i).
  func testTheReconnectMarkIsInWhatTheHeadlineReadsAs() {
    let c = content(makeState(phase: .work), connection: .reconnecting(attempt: 1))

    XCTAssertTrue(c.spokenHeadline.contains("(reconnecting)"), c.spokenHeadline)
  }

  // MARK: Private

  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func content(
    _ state: DaemonState?,
    connection: DaemonClient.Connection = .connected,
    tasks: TaskList = TaskList(),
    error: String? = nil,
    registrationFailed: Bool = false,
    startStalled: Bool = false,
    panel: WindowPanel? = nil,
  ) -> MainWindowContent {
    MainWindowContent(
      state: state,
      connection: connection,
      status: ServiceStatus.of(connection: connection, registrationFailed: registrationFailed, startStalled: startStalled),
      tasks: tasks,
      error: error,
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

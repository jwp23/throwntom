import XCTest
@testable import ThrowntomClient

final class TimerActionsTests: XCTestCase {

  // MARK: Internal

  func testIdleOffersStartSkipTodayAndSnoozeOnlyWhenMorningPending() {
    XCTAssertEqual(TimerActions.available(for: state(.idle)), [.start, .newCycle, .skipToday])
    XCTAssertEqual(TimerActions.available(for: state(.idle, morningPending: true)), [.start, .newCycle, .snooze, .skipToday])
  }

  func testRunningPhasesOfferPauseSkipAndEndingTheDay() {
    for phase in [DaemonState.Phase.work, .shortBreak, .longBreak] {
      XCTAssertEqual(TimerActions.available(for: state(phase)), [.pause, .skip, .skipToday], "\(phase)")
    }
  }

  /// Skip ends the running phase, so there is nothing to end unless one is running.
  func testSkipIsOfferedOnlyWhileAPhaseIsRunning() {
    for phase in [DaemonState.Phase.idle, .paused, .awaitingConfirm] {
      XCTAssertFalse(TimerActions.available(for: state(phase)).contains(.skip), "\(phase)")
    }
  }

  func testPausedOffersResumeAndEndingTheDay() {
    XCTAssertEqual(TimerActions.available(for: state(.paused)), [.resume, .skipToday])
  }

  func testAwaitingConfirmOffersConfirmSnoozeNewCycleAndEndingTheDay() {
    XCTAssertEqual(
      TimerActions.available(for: state(.awaitingConfirm)),
      [.confirm, .snooze, .newCycle, .skipToday],
    )
  }

  func testVerbsAndHints() {
    XCTAssertEqual(TimerAction.start.verb, .start)
    XCTAssertEqual(TimerAction.skipToday.verb, .skipToday)
    XCTAssertEqual(TimerAction.skip.verb, .skip)
    XCTAssertNil(TimerAction.snooze.verb)
    XCTAssertEqual(TimerAction.start.shortcutHint, "⌘R")
    XCTAssertEqual(TimerAction.confirm.shortcutHint, "⇧⏎")
    XCTAssertEqual(TimerAction.pause.shortcutHint, "⌘⇧P")
    XCTAssertEqual(TimerAction.resume.shortcutHint, "⌘⇧P")
    XCTAssertEqual(TimerAction.snooze.shortcutHint, "⌘⇧S")
    XCTAssertEqual(TimerAction.skipToday.shortcutHint, "")
    XCTAssertEqual(TimerAction.skip.shortcutHint, "⌘K")
    XCTAssertEqual(TimerAction.skip.title, "Skip")
    XCTAssertEqual(TimerAction.snooze.title, "Snooze \(TimerActions.defaultSnoozeMinutes) min")
  }

  func testHelpTextAppendsTheShortcutOnlyWhenThereIsOne() {
    XCTAssertEqual(TimerAction.start.helpText, "Start (⌘R)")
    XCTAssertEqual(TimerAction.snooze.helpText, "Snooze 10 min (⌘⇧S)")
    XCTAssertEqual(TimerAction.skipToday.helpText, "Done for Today")
    XCTAssertEqual(TimerAction.newCycle.helpText, "New Cycle")
  }

  func testPauseOrResumeOffersResumeOnlyWhilePaused() {
    XCTAssertEqual(TimerActions.pauseOrResume(for: .paused), .resume)
    XCTAssertEqual(TimerActions.pauseOrResume(for: .work), .pause)
    XCTAssertEqual(TimerActions.pauseOrResume(for: .idle), .pause)
    XCTAssertEqual(TimerActions.pauseOrResume(for: nil), .pause, "no state yet reads as not paused")
  }

  /// throwntom-46y. Stop is a suspend, so an idle timer can owe the break it earned: the daemon
  /// says which in `owed_stage`, and without reading it the chip says Start over a window whose
  /// title reads Idle and cannot say which phase the press begins.
  func testStartNamesThePhaseAnIdleStartWouldEnter() {
    XCTAssertEqual(
      TimerActions.startTitle(for: state(.idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))),
      "Start Short break",
    )
    XCTAssertEqual(
      TimerActions.startTitle(for: state(.idle, owedStage: DaemonState.Stage(state: .work, duration: 1500))),
      "Start Pomodoro",
    )
  }

  /// The daemon publishes an owed stage only while idle, and a client with no state at all has
  /// nothing to name. Both fall back to the plain verb rather than inventing a phase.
  func testStartIsThePlainVerbWhenNothingIsOwed() {
    XCTAssertEqual(TimerActions.startTitle(for: state(.work)), TimerAction.start.title)
    XCTAssertEqual(TimerActions.startTitle(for: nil), TimerAction.start.title)
  }

  /// An ended day still owes a phase, and Start is still offered there (`available(for:)`), so the
  /// title has to answer on that screen too.
  func testAnEndedDayStillNamesWhatStartWouldBegin() {
    let ended = state(.idle, dayEnded: true, owedStage: DaemonState.Stage(state: .work, duration: 1500))
    XCTAssertEqual(TimerActions.startTitle(for: ended), "Start Pomodoro")
  }

  // MARK: Private

  private func state(
    _ phase: DaemonState.Phase,
    morningPending: Bool = false,
    dayEnded: Bool = false,
    owedStage: DaemonState.Stage? = nil,
  ) -> DaemonState {
    DaemonState(
      state: phase,
      phaseEndAt: nil,
      pausedRemaining: 0,
      pausedFrom: .idle,
      completedToday: 0,
      workSessionsInBlock: 0,
      longBreakEvery: 4,
      nextStage: nil,
      owedStage: owedStage,
      morningPending: morningPending,
      snoozeUntil: nil,
      statusLine: "",
      focusedTaskIds: [],
      reminderRings: 0,
      dayEnded: dayEnded,
      floatWindowWhenWaiting: false,
      pausedTooLong: false,
      bounceDockWhenPaused: true,
    )
  }

}

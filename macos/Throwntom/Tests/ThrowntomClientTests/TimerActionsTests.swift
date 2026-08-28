import XCTest
@testable import ThrowntomClient

final class TimerActionsTests: XCTestCase {

  // MARK: Internal

  func testIdleOffersStartSkipTodayAndSnoozeOnlyWhenMorningPending() {
    XCTAssertEqual(TimerActions.available(for: state(.idle)), [.start, .newCycle, .skipToday])
    XCTAssertEqual(TimerActions.available(for: state(.idle, morningPending: true)), [.start, .newCycle, .snooze, .skipToday])
  }

  func testRunningPhasesOfferPauseOnly() {
    for phase in [DaemonState.Phase.work, .shortBreak, .longBreak] {
      XCTAssertEqual(TimerActions.available(for: state(phase)), [.pause], "\(phase)")
    }
  }

  func testPausedOffersResume() {
    XCTAssertEqual(TimerActions.available(for: state(.paused)), [.resume])
  }

  func testAwaitingConfirmOffersConfirmSnoozeNewCycle() {
    XCTAssertEqual(TimerActions.available(for: state(.awaitingConfirm)), [.confirm, .snooze, .newCycle])
  }

  func testVerbsAndHints() {
    XCTAssertEqual(TimerAction.start.verb, .start)
    XCTAssertEqual(TimerAction.skipToday.verb, .skipToday)
    XCTAssertNil(TimerAction.snooze.verb)
    XCTAssertEqual(TimerAction.start.shortcutHint, "⌘R")
    XCTAssertEqual(TimerAction.confirm.shortcutHint, "⏎")
    XCTAssertEqual(TimerAction.pause.shortcutHint, "⌘P")
    XCTAssertEqual(TimerAction.resume.shortcutHint, "⌘P")
    XCTAssertEqual(TimerAction.snooze.shortcutHint, "⌘⇧S")
    XCTAssertEqual(TimerAction.skipToday.shortcutHint, "")
    XCTAssertEqual(TimerAction.snooze.title, "Snooze \(TimerActions.defaultSnoozeMinutes) min")
  }

  func testHelpTextAppendsTheShortcutOnlyWhenThereIsOne() {
    XCTAssertEqual(TimerAction.start.helpText, "Start (⌘R)")
    XCTAssertEqual(TimerAction.snooze.helpText, "Snooze 10 min (⌘⇧S)")
    XCTAssertEqual(TimerAction.skipToday.helpText, "Skip Today")
    XCTAssertEqual(TimerAction.newCycle.helpText, "New Cycle")
  }

  func testPauseOrResumeOffersResumeOnlyWhilePaused() {
    XCTAssertEqual(TimerActions.pauseOrResume(for: .paused), .resume)
    XCTAssertEqual(TimerActions.pauseOrResume(for: .work), .pause)
    XCTAssertEqual(TimerActions.pauseOrResume(for: .idle), .pause)
    XCTAssertEqual(TimerActions.pauseOrResume(for: nil), .pause, "no state yet reads as not paused")
  }

  // MARK: Private

  private func state(_ phase: DaemonState.Phase, morningPending: Bool = false) -> DaemonState {
    DaemonState(
      state: phase,
      phaseEndAt: nil,
      pausedRemaining: 0,
      completedToday: 0,
      workSessionsInBlock: 0,
      longBreakEvery: 4,
      nextStage: nil,
      morningPending: morningPending,
      snoozeUntil: nil,
      statusLine: "",
      focusedTaskIds: [],
    )
  }

}

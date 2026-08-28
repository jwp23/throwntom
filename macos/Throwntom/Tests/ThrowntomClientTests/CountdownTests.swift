import XCTest
@testable import ThrowntomClient

final class CountdownTests: XCTestCase {

  // MARK: Internal

  func testReplacesRemainingForRunningPhase() {
    let now = Date()
    let s = state(.work, endsIn: 754.9, line: "Pomodoro  12:34  Today: 3  Cycle: 1/4", now: now)
    XCTAssertEqual(Countdown.tickedStatusLine(s, now: now), "Pomodoro  12:34  Today: 3  Cycle: 1/4")
    XCTAssertEqual(Countdown.tickedStatusLine(s, now: now.addingTimeInterval(60)), "Pomodoro  11:34  Today: 3  Cycle: 1/4")
  }

  func testClampsAtZeroAfterPhaseEnd() {
    let now = Date()
    let s = state(.shortBreak, endsIn: -5, line: "Short break  00:03  Today: 3  Cycle: 1/4", now: now)
    XCTAssertEqual(Countdown.tickedStatusLine(s, now: now), "Short break  00:00  Today: 3  Cycle: 1/4")
  }

  func testLeavesIdlePausedAndConfirmLinesAlone() {
    let now = Date()
    for (phase, line) in [
      (DaemonState.Phase.idle, "Idle  Today: 0  Cycle: 0/4"),
      (.paused, "Paused  10:00  Today: 3  Cycle: 1/4"),
      (.awaitingConfirm, "Confirm to continue  Today: 4  Cycle: 4/4"),
    ] {
      let s = state(phase, endsIn: 30, line: line, now: now)
      XCTAssertEqual(Countdown.tickedStatusLine(s, now: now.addingTimeInterval(20)), line)
    }
  }

  func testFormatRemainingMatchesGo() {
    XCTAssertEqual(Countdown.formatRemaining(0), "00:00")
    XCTAssertEqual(Countdown.formatRemaining(-3), "00:00")
    XCTAssertEqual(Countdown.formatRemaining(59.9), "00:59")
    XCTAssertEqual(Countdown.formatRemaining(1500), "25:00")
    XCTAssertEqual(Countdown.formatRemaining(6000), "100:00")
  }

  // MARK: Private

  private func state(_ phase: DaemonState.Phase, endsIn seconds: TimeInterval?, line: String, now: Date) -> DaemonState {
    DaemonState(
      state: phase,
      phaseEndAt: seconds.map { now.addingTimeInterval($0) },
      pausedRemaining: 0,
      completedToday: 3,
      workSessionsInBlock: 1,
      longBreakEvery: 4,
      nextStage: nil,
      morningPending: false,
      snoozeUntil: nil,
      statusLine: line,
      focusedTaskIds: [],
    )
  }

}

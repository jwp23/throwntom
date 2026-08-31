import XCTest
@testable import ThrowntomClient

final class PhaseDisplayTests: XCTestCase {
  func testEveryPhaseHasAName() {
    XCTAssertEqual(DaemonState.Phase.idle.displayName, "Idle")
    XCTAssertEqual(DaemonState.Phase.work.displayName, "Pomodoro")
    XCTAssertEqual(DaemonState.Phase.shortBreak.displayName, "Short break")
    XCTAssertEqual(DaemonState.Phase.longBreak.displayName, "Long break")
    XCTAssertEqual(DaemonState.Phase.awaitingConfirm.displayName, "Confirm")
    XCTAssertEqual(DaemonState.Phase.paused.displayName, "Paused")
  }

  func testNextStageSummaryTruncatesToWholeMinutes() {
    XCTAssertEqual(DaemonState.Stage(state: .work, duration: 1500).summary, "Pomodoro 25 min")
    XCTAssertEqual(DaemonState.Stage(state: .shortBreak, duration: 90).summary, "Short break 1 min")
    XCTAssertEqual(DaemonState.Stage(state: .longBreak, duration: 30).summary, "Long break 0 min")
  }
}

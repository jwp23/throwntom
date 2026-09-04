import XCTest
@testable import ThrowntomClient

/// Lunch is a phase the daemon can publish and a verb the client can send. It is chosen rather
/// than earned (`internal/engine/engine.go`), so nothing in the timer's own flow leads to it.
final class LunchPhaseTests: XCTestCase {
  func testLunchDecodesFromTheDaemonsName() throws {
    let json = #"{"state":"lunch","phase_end_at":null,"paused_remaining":0,"paused_from":"idle","completed_today":0,"work_sessions_in_block":0,"long_break_every":4,"next_stage":null,"owed_stage":null,"morning_pending":false,"snooze_until":null,"status_line":"Lunch","focused_task_ids":[],"reminder_rings":0,"day_ended":false,"float_window_when_waiting":false}"#

    let state = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(json.utf8))

    XCTAssertEqual(state.state, .lunch)
  }

  func testLunchIsNamedInTheWindow() {
    XCTAssertEqual(DaemonState.Phase.lunch.displayName, "Lunch")
  }

  func testLunchPostsToItsOwnTimerVerb() {
    XCTAssertEqual(TimerAction.lunch.verb, .lunch)
    XCTAssertEqual(TimerVerb.lunch.rawValue, "lunch")
    XCTAssertEqual(TimerAction.lunch.title, "Lunch")
  }

  /// The chip row is not where lunch is offered, so it carries no key hint either; the Timer menu
  /// is its only home until the chip row's own crowding is settled.
  func testLunchIsNotOfferedAsAChipInAnyState() {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .lunch, .awaitingConfirm, .paused] {
      XCTAssertFalse(
        TimerActions.available(for: makeClientState(phase: phase)).contains(.lunch),
        "\(phase) offers lunch as a chip",
      )
    }
    XCTAssertTrue(TimerAction.lunch.shortcutHint.isEmpty)
  }

  /// A running lunch offers what every other running phase offers.
  func testLunchOffersTheRunningPhaseVerbs() {
    XCTAssertEqual(TimerActions.available(for: makeClientState(phase: .lunch)), [.pause, .skip, .skipToday])
  }
}

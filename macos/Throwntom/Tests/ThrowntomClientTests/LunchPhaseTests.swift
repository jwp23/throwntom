import XCTest
@testable import ThrowntomClient

/// Lunch is a phase the daemon can publish and a verb the client can send. It is chosen rather
/// than earned (`internal/engine/engine.go`), so nothing in the timer's own flow leads to it.
///
/// Decoding the wire name is covered by `StateDecodingTests.testDecodesEveryPhaseName`, which
/// builds its document from the one State fixture the whole target shares; a second literal here
/// would only rot the next time the daemon gains a field.
final class LunchPhaseTests: XCTestCase {
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

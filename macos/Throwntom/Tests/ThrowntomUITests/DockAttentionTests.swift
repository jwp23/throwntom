import Foundation
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What each change in the daemon's state means for the Dock. The daemon decides *that* it wants
/// the user's eye — an unanswered reminder, or a pause it has been keeping the clock on; the app
/// decides only when to start and stop asking for it.
final class DockAttentionTests: XCTestCase {

  // MARK: Internal

  func testAnOrdinaryPhaseAsksForNothing() {
    XCTAssertEqual(decide(from: nil, to: makeState(phase: .work)), .unchanged)
  }

  func testAReminderStillAsksForAttention() {
    XCTAssertEqual(
      decide(from: makeState(phase: .work), to: makeState(phase: .awaitingConfirm, nextStage: shortBreak)),
      .request,
    )
  }

  func testAPauseThatHasLastedTooLongAsksForAttention() {
    XCTAssertEqual(decide(from: pausedState(), to: pausedState(tooLong: true)), .request)
  }

  /// A pause inside its threshold is an ordinary pause: the user knows they paused it.
  func testAPauseInsideItsThresholdAsksForNothing() {
    XCTAssertEqual(decide(from: makeState(phase: .work), to: pausedState()), .unchanged)
  }

  /// The request already outstanding is what keeps the Dock bouncing. Asking again would leak the
  /// first request's identifier, leaving nothing able to call the bounce off.
  func testAPauseThatStaysTooLongAsksOnlyOnce() {
    XCTAssertEqual(decide(from: pausedState(tooLong: true), to: pausedState(tooLong: true)), .unchanged)
  }

  /// The event stream sends a frame per tick. The request outstanding is still wanted on every one
  /// of them, and calling it off would end the bounce with the reminder unanswered.
  func testRepeatedFramesOfTheSameReminderLeaveTheDockAlone() {
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    XCTAssertEqual(decide(from: waiting, to: waiting), .unchanged)
  }

  /// The app can be launched, or reconnected, into a pause that was forgotten long before it
  /// started following the daemon. It is still forgotten.
  func testTheFirstStateTheAppEverSeesCanAlreadyBeAForgottenPause() {
    XCTAssertEqual(decide(from: nil, to: pausedState(tooLong: true)), .request)
  }

  func testResumingAForgottenPauseCallsTheBounceOff() {
    XCTAssertEqual(decide(from: pausedState(tooLong: true), to: makeState(phase: .work)), .cancel)
  }

  func testAnsweringAReminderCallsTheBounceOff() {
    XCTAssertEqual(
      decide(from: makeState(phase: .awaitingConfirm, nextStage: shortBreak), to: makeState(phase: .work)),
      .cancel,
    )
  }

  /// Nothing was asked for, so there is nothing to call off.
  func testAnOrdinaryPhaseFollowingAnotherCallsNothingOff() {
    XCTAssertEqual(decide(from: makeState(phase: .work), to: makeState(phase: .shortBreak)), .unchanged)
  }

  /// bounce_dock_when_paused off means the pause bounce is declined, not merely deferred: the
  /// forgotten pause still asks for nothing.
  func testBounceDockWhenPausedOffAsksForNothing() {
    XCTAssertEqual(
      decide(from: pausedState(), to: pausedState(tooLong: true, bounceDockWhenPaused: false)),
      .unchanged,
    )
  }

  /// A live config reload can turn the setting off while a bounce it started is still running.
  /// Without an explicit cancel here the Dock would keep bouncing until the pause is resumed or
  /// the reminder underneath it changes, neither of which the user asked for.
  func testTurningBounceDockWhenPausedOffLiveCancelsAnActiveBounce() {
    XCTAssertEqual(
      decide(from: pausedState(tooLong: true), to: pausedState(tooLong: true, bounceDockWhenPaused: false)),
      .cancel,
    )
  }

  // MARK: Private

  private let shortBreak = DaemonState.Stage(state: .shortBreak, duration: 300)

  private func decide(from previous: DaemonState?, to current: DaemonState) -> DockAttention {
    DockAttention.decide(from: previous, to: current)
  }

  private func pausedState(tooLong: Bool = false, bounceDockWhenPaused: Bool = true) -> DaemonState {
    makeState(
      phase: .paused,
      pausedRemaining: 600,
      pausedFrom: .work,
      pausedTooLong: tooLong,
      bounceDockWhenPaused: bounceDockWhenPaused,
    )
  }

}

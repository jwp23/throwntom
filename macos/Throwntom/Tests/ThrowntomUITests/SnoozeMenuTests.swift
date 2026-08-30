import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeMenuTests: XCTestCase {

  func testTheMenuOffersEveryPresetThenCustomThenTheUndo() {
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm))
    XCTAssertEqual(menu.items.map(\.action), [
      .snooze(minutes: 10),
      .snooze(minutes: 15),
      .snooze(minutes: 30),
      .snooze(minutes: 60),
      .custom,
      .cancel,
    ])
    XCTAssertEqual(menu.items.map(\.title), [
      "10 minutes",
      "15 minutes",
      "30 minutes",
      "1 hour",
      "Custom…",
      "Cancel Snooze",
    ])
  }

  func testTheUndoIsSeparatedFromTheDurations() {
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm))
    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.last?.map(\.action), [.cancel])
  }

  func testDurationsNeedAReminderToDefer() {
    // Mid-pomodoro nothing is waiting on an answer, so there is nothing to snooze.
    let running = MenuModel.snooze(state: makeState(phase: .work))
    XCTAssertTrue(running.items.filter { $0.action != .cancel }.allSatisfy { !$0.isEnabled })

    let waiting = MenuModel.snooze(state: makeState(phase: .awaitingConfirm))
    XCTAssertTrue(waiting.items.filter { $0.action != .cancel }.allSatisfy(\.isEnabled))
  }

  func testCancelNeedsASnoozeToCancel() {
    let notSnoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm))
    XCTAssertFalse(notSnoozed.items.last?.isEnabled ?? true)

    let snoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm, snoozeUntil: Date()))
    XCTAssertTrue(snoozed.items.last?.isEnabled ?? false)
  }

  /// A snooze already running can be replaced with a different one, so the durations stay live.
  /// Otherwise changing 10 minutes to an hour would mean cancelling first — which rings the
  /// reminder you were trying to put off.
  func testASnoozeCanBeReplacedWithoutCancellingItFirst() {
    let snoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm, snoozeUntil: Date()))
    XCTAssertTrue(snoozed.items.filter { $0.action != .cancel }.allSatisfy(\.isEnabled))
  }

  func testWithNoDaemonNothingIsOffered() {
    let menu = MenuModel.snooze(state: nil)
    XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
  }

  func testNoSnoozeItemBindsAKey() {
    // ⌘⇧S is the default snooze and stays on the Timer menu; the durations are pointer-driven.
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm))
    XCTAssertTrue(menu.items.allSatisfy { $0.shortcut == nil })
  }

}

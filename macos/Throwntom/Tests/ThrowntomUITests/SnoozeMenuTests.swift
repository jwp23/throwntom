import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeMenuTests: XCTestCase {

  func testTheMenuOffersEveryPresetThenCustomThenTheUndo() {
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
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
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.last?.map(\.action), [.cancel])
  }

  func testDurationsNeedAReminderToDefer() {
    // Mid-pomodoro nothing is waiting on an answer, so there is nothing to snooze.
    let running = MenuModel.snooze(state: makeState(phase: .work), daemonAvailable: true)
    XCTAssertTrue(running.items.filter { $0.action != .cancel }.allSatisfy { !$0.isEnabled })

    let waiting = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
    XCTAssertTrue(waiting.items.filter { $0.action != .cancel }.allSatisfy(\.isEnabled))
  }

  func testCancelNeedsASnoozeToCancel() {
    let notSnoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
    XCTAssertFalse(notSnoozed.items.last?.isEnabled ?? true)

    let snoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm, snoozeUntil: Date()), daemonAvailable: true)
    XCTAssertTrue(snoozed.items.last?.isEnabled ?? false)
  }

  /// A snooze already running can be replaced with a different one, so the durations stay live.
  /// Otherwise changing 10 minutes to an hour would mean cancelling first — which rings the
  /// reminder you were trying to put off.
  func testASnoozeCanBeReplacedWithoutCancellingItFirst() {
    let snoozed = MenuModel.snooze(state: makeState(phase: .awaitingConfirm, snoozeUntil: Date()), daemonAvailable: true)
    XCTAssertTrue(snoozed.items.filter { $0.action != .cancel }.allSatisfy(\.isEnabled))
  }

  func testWithNoDaemonNothingIsOffered() {
    let menu = MenuModel.snooze(state: nil, daemonAvailable: true)
    XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
  }

  /// The service-down screens withdraw every command line for the daemon (throwntom-0jd); a
  /// snooze is one, so `daemonAvailable: false` must empty the menu even off a retained state
  /// that still says a reminder is waiting or a snooze is running — otherwise the durations, and
  /// Cancel Snooze off a stale `snoozeUntil`, would go on dispatching into a daemon that is gone.
  func testWithNoDaemonEverythingIsDisabledEvenOffARetainedState() {
    let waiting = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: false)
    XCTAssertTrue(waiting.items.allSatisfy { !$0.isEnabled })

    let snoozed = MenuModel.snooze(state: makeState(phase: .work, snoozeUntil: Date()), daemonAvailable: false)
    XCTAssertTrue(snoozed.items.allSatisfy { !$0.isEnabled })
  }

  func testNoSnoozeItemBindsAKey() {
    // ⌘⇧S is the default snooze and stays on the Timer menu; the durations are pointer-driven.
    let menu = MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
    XCTAssertTrue(menu.items.allSatisfy { $0.shortcut == nil })
  }

  /// `AppMenus` greys the whole "Snooze For" submenu off this condition. A submenu of dead items
  /// says the same thing one level down and one click later than a dead parent does.
  func testTheMenuHasNothingLiveWhenThereIsNeitherAReminderNorASnooze() {
    XCTAssertFalse(MenuModel.snooze(state: makeState(phase: .work), daemonAvailable: true).items.contains(where: \.isEnabled))
    XCTAssertFalse(MenuModel.snooze(state: nil, daemonAvailable: true).items.contains(where: \.isEnabled))

    // Either half on its own is enough to keep it open.
    XCTAssertTrue(MenuModel.snooze(state: makeState(phase: .awaitingConfirm), daemonAvailable: true)
      .items.contains(where: \.isEnabled))
    XCTAssertTrue(MenuModel.snooze(state: makeState(phase: .work, snoozeUntil: Date()), daemonAvailable: true)
      .items.contains(where: \.isEnabled))
  }

}

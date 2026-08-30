import AppKit
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// Whether the window sits above other applications' windows while a reminder is outstanding, and
/// the guarantee that comes with it: raising the window must never take the keyboard.
@MainActor
final class WindowElevationTests: XCTestCase {

  // MARK: Internal

  func testTheWindowDoesNotFloatWhileTheSettingIsOff() {
    XCTAssertFalse(WindowElevation.floats(during: waiting(floatWhenWaiting: false), connection: .connected))
  }

  func testTheWindowFloatsWhileAReminderIsWaiting() {
    XCTAssertTrue(WindowElevation.floats(during: waiting(floatWhenWaiting: true), connection: .connected))
  }

  /// Confirming ends the wait by leaving `awaitingConfirm`, and the window drops back with it.
  func testConfirmingTheReminderStopsTheFloat() {
    let confirmed = makeState(phase: .shortBreak, floatWhenWaiting: true)
    XCTAssertFalse(WindowElevation.floats(during: confirmed, connection: .connected))
  }

  /// A snooze the daemon has accepted is an answer: nothing is outstanding until it runs out, so
  /// the window must not stay in front through it.
  func testSnoozingTheReminderStopsTheFloat() {
    let snoozed = makeState(
      phase: .awaitingConfirm,
      nextStage: shortBreak,
      snoozeUntil: Date(timeIntervalSince1970: 1),
      floatWhenWaiting: true,
    )
    XCTAssertFalse(WindowElevation.floats(during: snoozed, connection: .connected))
  }

  /// The morning nudge is a reminder waiting to be answered too, and `float_window_when_waiting`
  /// says "when waiting" rather than naming one of them.
  func testTheMorningNudgeFloatsTheWindowToo() {
    let morning = makeState(phase: .idle, morningPending: true, floatWhenWaiting: true)
    XCTAssertTrue(WindowElevation.floats(during: morning, connection: .connected))
  }

  func testAStateTheAppCannotReadDoesNotFloatTheWindow() {
    XCTAssertFalse(WindowElevation.floats(during: nil, connection: .connected))
  }

  /// A daemon that goes down leaves its last state behind, and that state can still say a reminder
  /// is waiting. Floating on the strength of it would put the window over everything for as long as
  /// the daemon stayed down, with nothing left able to answer the reminder and lower it again.
  func testALostDaemonLetsTheWindowBackDown() {
    let waitingState = waiting(floatWhenWaiting: true)

    let lost: [DaemonClient.Connection] = [
      .reconnecting(attempt: 1),
      .connecting,
      .startingDaemon,
      .stopped,
    ]
    for connection in lost {
      XCTAssertFalse(
        WindowElevation.floats(during: waitingState, connection: connection),
        "a \(connection) daemon must not hold the window in front",
      )
    }
  }

  /// Joe's requirement, 2026-08-29: the window may come to the front, but it must never steal the
  /// keyboard — "if it stole focus I could be in the middle of typing and have to go back to my
  /// original window". Window level and key focus are separate mechanisms: only activating or
  /// ordering the window front takes the keyboard, and raising the level does neither.
  ///
  /// `isVisible` is the assertion with teeth. An unbundled `swift test` process is not an
  /// activated GUI app, so `isKeyWindow` cannot become true here however badly this behaves —
  /// it is asserted to say what is being promised, not because it could catch a breach. Adding
  /// `makeKeyAndOrderFront` to `apply` was checked to fail this test, and it fails on `isVisible`.
  func testRaisingTheWindowNeverMakesItKey() {
    let window = makeWindow()

    WindowElevation.apply(true, to: window)

    XCTAssertEqual(window.level, .floating)
    XCTAssertFalse(window.isKeyWindow, "floating must not take the keyboard")
    XCTAssertFalse(window.isMainWindow, "floating must not make the window main")
    XCTAssertFalse(window.isVisible, "floating must not order a closed window on screen")
  }

  func testTheWindowGoesBackToTheOrdinaryLevelWhenTheWaitEnds() {
    let window = makeWindow()

    WindowElevation.apply(true, to: window)
    WindowElevation.apply(false, to: window)

    XCTAssertEqual(window.level, .normal)
    XCTAssertFalse(window.isKeyWindow)
  }

  /// The half that reaches the real window: the level lands when the view joins the hierarchy,
  /// which is the moment there is a window to raise at all.
  func testTheLevelIsAppliedWhenTheViewJoinsAWindow() {
    let window = makeWindow()
    let view = ElevatedHostView()
    view.floating = true

    window.contentView?.addSubview(view)

    XCTAssertEqual(window.level, .floating)
    XCTAssertFalse(window.isVisible, "joining a window must not put it on screen")
  }

  func testTheLevelFollowsLaterChangesWhileInAWindow() {
    let window = makeWindow()
    let view = ElevatedHostView()
    window.contentView?.addSubview(view)

    view.floating = true
    XCTAssertEqual(window.level, .floating)

    view.floating = false
    XCTAssertEqual(window.level, .normal)
  }

  /// The view is a handle on the window, not something to click: it is hung behind the whole
  /// window, so a view that answered hit tests would swallow them.
  func testTheHostViewTakesNoClicks() {
    XCTAssertNil(ElevatedHostView().hitTest(NSPoint(x: 1, y: 1)))
  }

  // MARK: Private

  private let shortBreak = DaemonState.NextStage(state: .shortBreak, duration: 300)

  private func makeWindow() -> NSWindow {
    NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: true,
    )
  }

  private func waiting(floatWhenWaiting: Bool) -> DaemonState {
    makeState(phase: .awaitingConfirm, nextStage: shortBreak, floatWhenWaiting: floatWhenWaiting)
  }

}

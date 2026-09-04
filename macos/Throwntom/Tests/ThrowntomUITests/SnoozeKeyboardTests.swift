import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// Who owns the Return key while the custom-snooze field is open.
///
/// Confirm is bound to bare Return in the Timer menu, and a main menu's key equivalent is offered
/// the keystroke before the focused text field ever sees it. The Timer menu already gives Return up
/// for the inline new-task row; the duration field needs the same, and needs it in exactly the state
/// it is opened from — `awaiting_confirm` offers Confirm and Snooze together, so both verbs are live
/// while the user is typing a number into the field.
@MainActor
final class SnoozeKeyboardTests: XCTestCase {

  // MARK: Internal

  /// Without this, typing `45` and pressing Return confirmed the stage instead of snoozing it —
  /// answering the very reminder the user was deferring, and `SnoozeEntryRow.submit` never ran.
  func testTheTimerMenuGivesUpReturnWhileTheDurationFieldIsOpen() async throws {
    let menus = try await makeMenus()
    menus.environment.windowModel.isEnteringSnooze = true

    XCTAssertFalse(try XCTUnwrap(menus.timerMenu.item(for: .confirm)).isEnabled)
  }

  /// And takes it back when the field closes: a menu item disabled for good would be a worse bug
  /// than the one being fixed, and a guard that never lets go proves nothing about the guard.
  func testTheTimerMenuKeepsReturnWhileNoFieldIsOpen() async throws {
    let menus = try await makeMenus()

    XCTAssertFalse(menus.environment.windowModel.isEnteringSnooze)
    XCTAssertTrue(try XCTUnwrap(menus.timerMenu.item(for: .confirm)).isEnabled)
  }

  // MARK: Private

  /// Menus over a daemon waiting to be confirmed — the one state that offers Confirm and Snooze at
  /// once, and so the only state the clash can happen in.
  private func makeMenus() async throws -> AppMenus {
    let transport = try StubTransport(states: [makeState(phase: .awaitingConfirm)])
    let environment = AppEnvironment(transport: transport)
    addTeardownBlock { @MainActor in environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let menus = AppMenus(environment: environment)
    XCTAssertTrue(menus.daemonAvailable)
    return menus
  }

}

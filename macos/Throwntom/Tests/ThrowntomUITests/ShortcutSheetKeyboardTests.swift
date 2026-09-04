import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// Who owns the Return key while the keyboard-shortcuts sheet is open.
///
/// The same clash as the duration field, one surface over: the sheet's Done button is the default
/// action, which is bare Return, and Confirm is bound to bare Return in the Timer menu. A main
/// menu's key equivalent is offered the keystroke first, so Return confirmed the stage behind a
/// sheet the user was only reading — and behind a sheet, where they could not see it happen.
///
/// This is a guard, not a rebinding: Confirm keeps bare Return and gives it up for as long as
/// something in front of it is using the key.
@MainActor
final class ShortcutSheetKeyboardTests: XCTestCase {

  // MARK: Internal

  func testTheTimerMenuGivesUpReturnWhileTheShortcutSheetIsOpen() async throws {
    let menus = try await makeMenus()
    menus.environment.windowModel.showsShortcuts = true

    XCTAssertFalse(try XCTUnwrap(menus.timerMenu.item(for: .confirm)).isEnabled)
  }

  /// And takes it back when the sheet closes. A guard that never lets go would be a worse bug than
  /// the one it fixes, and proves nothing about the guard.
  func testTheTimerMenuTakesReturnBackWhenTheSheetCloses() async throws {
    let menus = try await makeMenus()
    menus.environment.windowModel.showsShortcuts = true
    menus.environment.windowModel.showsShortcuts = false

    XCTAssertTrue(try XCTUnwrap(menus.timerMenu.item(for: .confirm)).isEnabled)
  }

  // MARK: Private

  /// Menus over a daemon waiting to be confirmed — the only state that offers Confirm at all, and
  /// so the only state the clash can happen in.
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

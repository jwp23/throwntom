import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - LunchMenuTests

/// The lengths behind the Timer menu's "Lunch" submenu (`AppMenus.lunchMenu`), which offers the
/// same choices as the chip's own split chip.
final class LunchMenuTests: XCTestCase {

  func testTheMenuOffersThirtyAndSixtyMinutesThenACustomLength() {
    let menu = MenuModel.lunch(canStart: true)
    XCTAssertEqual(menu.items.map(\.action), [.start(minutes: 30), .start(minutes: 60), .custom])
    XCTAssertEqual(menu.items.map(\.title), ["30 minutes", "1 hour", "Custom…"])
  }

  /// There is no way out here, unlike the meeting and snooze pickers — Skip is already that —
  /// so the whole menu is one group.
  func testEveryChoiceIsOneGroup() {
    let menu = MenuModel.lunch(canStart: true)
    XCTAssertEqual(menu.groups.count, 1)
  }

  func testTheChoicesFollowWhetherLunchCanStart() {
    XCTAssertTrue(MenuModel.lunch(canStart: true).items.allSatisfy(\.isEnabled))
    XCTAssertTrue(MenuModel.lunch(canStart: false).items.allSatisfy { !$0.isEnabled })
  }

  func testNoLunchItemBindsAKey() {
    XCTAssertTrue(MenuModel.lunch(canStart: true).items.allSatisfy { $0.shortcut == nil })
  }

}

// MARK: - LunchMenuGateTests

/// When that submenu offers anything. `AppMenus.lunchMenu` asks the client rather than taking
/// `canStart` as a literal, and each of the three answers it withholds on is a state where a
/// length chosen from the menu bar would reach no daemon, or restart the hour already running.
@MainActor
final class LunchMenuGateTests: XCTestCase {

  // MARK: Internal

  func testTheLengthsAreOfferedOverADaemonThatIsNotAtLunch() async throws {
    let menus = try await makeMenus(phase: .idle)

    XCTAssertEqual(menus.lunchMenu.items.map(\.isEnabled), [true, true, true])
  }

  /// Starting lunch again would only restart the hour, so the submenu goes dim for its own phase.
  func testTheLengthsAreWithheldWhileLunchIsAlreadyRunning() async throws {
    let menus = try await makeMenus(phase: .lunch)

    XCTAssertEqual(menus.lunchMenu.items.map(\.isEnabled), [false, false, false])
  }

  /// A client still dialling takes commands, but there is no phase yet to say whether lunch is
  /// one of them, so the lengths wait for the first frame.
  func testTheLengthsAreWithheldUntilTheDaemonHasSentAState() throws {
    let menus = AppMenus(environment: AppEnvironment(transport: try StubTransport(states: [])))

    XCTAssertTrue(menus.daemonAvailable, "a client still dialling is one that takes commands")
    XCTAssertNil(menus.environment.client.state)
    XCTAssertEqual(menus.lunchMenu.items.map(\.isEnabled), [false, false, false])
  }

  func testTheLengthsAreWithheldWithNoDaemonToTakeThem() throws {
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      intents: MemoryServiceIntentStore(.stopped),
    )
    let menus = AppMenus(environment: environment)

    XCTAssertFalse(menus.daemonAvailable)
    XCTAssertEqual(menus.lunchMenu.items.map(\.isEnabled), [false, false, false])
  }

  // MARK: Private

  private func makeMenus(phase: DaemonState.Phase) async throws -> AppMenus {
    let environment = AppEnvironment(transport: try StubTransport(states: [makeState(phase: phase)]))
    addTeardownBlock { @MainActor in environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let menus = AppMenus(environment: environment)
    XCTAssertTrue(menus.daemonAvailable)
    return menus
  }

}

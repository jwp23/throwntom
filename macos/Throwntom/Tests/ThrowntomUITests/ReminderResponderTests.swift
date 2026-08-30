import UserNotifications
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What the reminder's buttons do when macOS hands the answer to the app. The responder
/// is taken from `AppEnvironment`, so these also pin down that the app wires it to its client.
@MainActor
final class ReminderResponderTests: XCTestCase {
  func testSnoozeButtonSnoozesTheDaemon() async throws {
    let transport = try StubTransport(states: [])
    let responder = AppEnvironment(transport: transport).responder
    let reported = expectation(description: "macOS is told the answer was handled")

    responder.respond(to: ReminderNotification.Action.snooze.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/snooze"])
    XCTAssertEqual(transport.commands.map(\.body), [#"{"minutes":10}"#])
  }

  func testConfirmButtonConfirmsTheStage() async throws {
    let transport = try StubTransport(states: [])
    let responder = AppEnvironment(transport: transport).responder
    let reported = expectation(description: "macOS is told the answer was handled")

    responder.respond(to: ReminderNotification.Action.confirm.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/confirm"])
  }

  func testDismissingTheReminderIsReportedWithoutTouchingTheDaemon() async throws {
    let transport = try StubTransport(states: [])
    let responder = AppEnvironment(transport: transport).responder
    let reported = expectation(description: "macOS is told the dismissal was handled")

    responder.respond(to: UNNotificationDismissActionIdentifier) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertTrue(transport.commands.isEmpty)
  }

  func testRefusedButtonSurfacesOnTheClientInsteadOfBeingSwallowed() async throws {
    let transport = try StubTransport(states: [])
    transport.commandStatus = 409
    let environment = AppEnvironment(transport: transport)
    let responder = environment.responder
    let reported = expectation(description: "macOS is told the answer was handled")

    responder.respond(to: ReminderNotification.Action.confirm.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertNotNil(environment.client.unresolvedError)
  }

  /// The last affordance that reaches the daemon. A banner posted before the service went down
  /// outlives it in Notification Center — `stopService()` clears the state that decides the banner,
  /// so nothing takes it back down — and its buttons were the one dispatch path with no service
  /// gate. Pressing one refused, and the refusal is written to `commandError`, which
  /// `unresolvedError` reports ahead of the stopped state: a fault note on the one screen whose
  /// whole claim is that nothing failed.
  func testAReminderButtonPressedWhileTheServiceIsStoppedTouchesNothingAndSaysNothing() async throws {
    let transport = try StubTransport(states: [])
    let presenter = StubReminderPresenter()
    let environment = AppEnvironment(
      transport: transport,
      presenter: presenter,
      intents: MemoryServiceIntentStore(.stopped),
    )
    let reported = expectation(description: "macOS is told the answer was handled")

    environment.responder.respond(to: ReminderNotification.Action.confirm.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertTrue(transport.commands.isEmpty, "there is no daemon to confirm to")
    XCTAssertNil(environment.client.unresolvedError, "a stopped service is not a fault")
  }

  /// A button that vanishes without doing what it says is a small lie. Pressing Confirm with no
  /// service behind it brings the window forward instead, where the screen this branch built says
  /// which of the three situations you are in and offers Start Timer Service — the answer to "why
  /// did nothing happen", rather than an alert invented for the occasion.
  func testAReminderButtonWithNoServiceBehindItShowsTheWindowThatExplainsWhy() async throws {
    let presenter = StubReminderPresenter()
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      presenter: presenter,
      intents: MemoryServiceIntentStore(.stopped),
    )
    let reported = expectation(description: "macOS is told the answer was handled")

    environment.responder.respond(to: ReminderNotification.Action.confirm.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertEqual(presenter.windowReveals, 1)
    XCTAssertEqual(presenter.withdrawals, 1, "and the banner it came from goes")
  }

  /// The reveal is for a dead press only. A button pressed against a live daemon confirms and
  /// leaves the user where they were.
  func testAReminderButtonWithADaemonBehindItDoesNotStealFocus() async throws {
    let presenter = StubReminderPresenter()
    let environment = AppEnvironment(transport: try StubTransport(states: []), presenter: presenter)
    let reported = expectation(description: "macOS is told the answer was handled")

    environment.responder.respond(to: ReminderNotification.Action.confirm.rawValue) { reported.fulfill() }

    await fulfillment(of: [reported], timeout: 5)
    XCTAssertEqual(presenter.windowReveals, 0)
  }

  /// And the banner itself goes, so the buttons are not left on screen doing nothing. Built from
  /// the parts rather than from `AppEnvironment` because this one calls `stopService()`, and the
  /// environment's registrar is the real `SMAppServiceRegistrar`: a test must not boot out the
  /// launch agent of the machine running it.
  func testStoppingTheServiceTakesTheReminderBannerDown() async throws {
    let presenter = StubReminderPresenter()
    let client = DaemonClient(transport: try StubTransport(states: []), registrar: RecordingRegistrar())
    let responder = ReminderResponder(client: client, presenter: presenter)

    client.stopService()
    await responder.present(client.state)

    XCTAssertEqual(client.serviceStatus, .stopped, "the stop has to have taken for the rest to mean anything")
    XCTAssertEqual(presenter.withdrawals, 1)
  }

  /// The withdrawal is for a service that is gone, not for every stateless moment: a client that
  /// has simply not heard from the daemon yet must leave an outstanding banner alone.
  func testADialledButSilentDaemonLeavesTheBannerAlone() async throws {
    let presenter = StubReminderPresenter()
    let client = DaemonClient(transport: try StubTransport(states: []), registrar: RecordingRegistrar())
    let responder = ReminderResponder(client: client, presenter: presenter)

    await responder.present(nil)

    XCTAssertEqual(client.serviceStatus, .reaching)
    XCTAssertEqual(presenter.withdrawals, 0)
  }

  func testTheReminderIsShownEvenWhileThrowntomIsFrontmost() {
    XCTAssertTrue(ReminderResponder.presentationOptions.contains(.banner))
  }

  /// A reminder that arrives while the window is frontmost is no less due than any other. The
  /// daemon plays nothing (ADR-007), and the banner's own sound is suppressed in the foreground
  /// unless the app asks for it here.
  func testTheReminderIsHeardEvenWhileThrowntomIsFrontmost() {
    XCTAssertTrue(ReminderResponder.presentationOptions.contains(.sound))
  }
}

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

  func testTheReminderIsShownEvenWhileThrowntomIsFrontmost() {
    XCTAssertTrue(ReminderResponder.presentationOptions.contains(.banner))
  }

  /// A reminder that arrives while the window is frontmost is no less due than any other. The
  /// daemon plays nothing (ADR-003), and the banner's own sound is suppressed in the foreground
  /// unless the app asks for it here.
  func testTheReminderIsHeardEvenWhileThrowntomIsFrontmost() {
    XCTAssertTrue(ReminderResponder.presentationOptions.contains(.sound))
  }
}

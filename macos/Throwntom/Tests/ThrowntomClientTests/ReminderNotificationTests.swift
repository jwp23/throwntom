import UserNotifications
import XCTest
@testable import ThrowntomClient

// MARK: - ReminderNotificationCommandTests

final class ReminderNotificationCommandTests: XCTestCase {
  func testActionsRoundTripThroughTheirIdentifiers() {
    for action in ReminderNotification.Action.allCases {
      XCTAssertEqual(ReminderNotification.action(for: action.rawValue), action)
    }
  }

  func testSystemActionsAreNotOurs() {
    XCTAssertNil(ReminderNotification.action(for: UNNotificationDefaultActionIdentifier))
    XCTAssertNil(ReminderNotification.action(for: UNNotificationDismissActionIdentifier))
  }

  func testActionTitlesMatchTheMenuBarWording() {
    XCTAssertEqual(ReminderNotification.Action.snooze.title, TimerAction.snooze.title)
    XCTAssertEqual(ReminderNotification.Action.confirm.title, TimerAction.confirm.title)
    XCTAssertEqual(ReminderNotification.Action.start.title, TimerAction.start.title)
    XCTAssertEqual(ReminderNotification.Action.skipToday.title, TimerAction.skipToday.title)
  }
}

// MARK: - ReminderNotificationAnswerTests

/// Drives the reminder actions against a real throwntomd, which is the only way
/// to prove the buttons reach the commands they claim to.
@MainActor
final class ReminderNotificationAnswerTests: XCTestCase {

  // MARK: Internal

  override func setUp() async throws {
    daemon = try DaemonHarness()
    try await daemon.start()
  }

  override func tearDown() {
    daemon.cleanup()
  }

  func testSnoozeActionSnoozesTheDaemon() async throws {
    let client = try await connectedClient()
    defer { client.stop() }
    XCTAssertNil(client.state?.snoozeUntil)

    try await ReminderNotification.answer(.snooze, using: client)

    try await waitUntil { client.state?.snoozeUntil != nil }
  }

  // MARK: Private

  private var daemon: DaemonHarness!

  private func connectedClient() async throws -> DaemonClient {
    let client = DaemonClient(
      transport: UnixSocketTransport(socketPath: daemon.socketPath),
      registrar: RecordingRegistrar(),
    )
    client.start()
    try await waitUntil { client.connection == .connected }
    return client
  }

}

// MARK: - ReminderNotificationRequestTests

@MainActor
final class ReminderNotificationRequestTests: XCTestCase {

  // MARK: Internal

  func testConfirmPostsTheConfirmVerb() async throws {
    let transport = RecordingTransport()
    try await ReminderNotification.answer(.confirm, using: client(transport))

    XCTAssertEqual(transport.requests.map(\.method), ["POST"])
    XCTAssertEqual(transport.requests.map(\.path), ["/v1/timer/confirm"])
    XCTAssertNil(transport.requests.first?.body)
  }

  func testSnoozePostsTheDefaultSnoozeMinutes() async throws {
    let transport = RecordingTransport()
    try await ReminderNotification.answer(.snooze, using: client(transport))

    XCTAssertEqual(transport.requests.map(\.path), ["/v1/timer/snooze"])
    let body = try XCTUnwrap(transport.requests.first?.body)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Int]
    XCTAssertEqual(decoded, ["minutes": TimerActions.defaultSnoozeMinutes])
  }

  func testStartPostsTheStartVerb() async throws {
    let transport = RecordingTransport()
    try await ReminderNotification.answer(.start, using: client(transport))

    XCTAssertEqual(transport.requests.map(\.path), ["/v1/timer/start"])
    XCTAssertNil(transport.requests.first?.body)
  }

  func testSkipTodayPostsTheSkipTodayVerb() async throws {
    let transport = RecordingTransport()
    try await ReminderNotification.answer(.skipToday, using: client(transport))

    XCTAssertEqual(transport.requests.map(\.path), ["/v1/timer/skip-today"])
    XCTAssertNil(transport.requests.first?.body)
  }

  // MARK: Private

  private func client(_ transport: RecordingTransport) -> DaemonClient {
    DaemonClient(transport: transport, registrar: RecordingRegistrar())
  }

}

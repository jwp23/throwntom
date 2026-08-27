import UserNotifications
import XCTest
@testable import ThrowntomClient

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
    }
}

/// Drives the reminder actions against a real throwntomd, which is the only way
/// to prove the buttons reach the commands they claim to.
@MainActor
final class ReminderNotificationAnswerTests: XCTestCase {
    var daemon: DaemonHarness!

    override func setUp() async throws {
        daemon = try DaemonHarness()
        try await daemon.start()
    }

    override func tearDown() {
        daemon.cleanup()
    }

    private func connectedClient() async throws -> DaemonClient {
        let client = DaemonClient(
            transport: UnixSocketTransport(socketPath: daemon.socketPath),
            registrar: RecordingRegistrar())
        client.start()
        try await waitUntil { client.connection == .connected }
        return client
    }

    func testSnoozeActionSnoozesTheDaemon() async throws {
        let client = try await connectedClient()
        defer { client.stop() }
        XCTAssertNil(client.state?.snoozeUntil)

        try await ReminderNotification.answer(.snooze, using: client)

        try await waitUntil { client.state?.snoozeUntil != nil }
    }
}

@MainActor
final class ReminderNotificationRequestTests: XCTestCase {
    private func client(_ transport: RecordingTransport) -> DaemonClient {
        DaemonClient(transport: transport, registrar: RecordingRegistrar())
    }

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
}

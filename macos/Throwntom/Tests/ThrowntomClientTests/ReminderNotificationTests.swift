import UserNotifications
import XCTest
@testable import ThrowntomClient

final class ReminderNotificationCommandTests: XCTestCase {
    func testParsesShowWithTitleAndBody() {
        XCTAssertEqual(
            ReminderNotification.command(from: ["show", "--title", "Throwntom", "--body", "Ready for a short break"]),
            .show(title: "Throwntom", body: "Ready for a short break"))
    }

    func testParsesShowWithFlagsInEitherOrder() {
        XCTAssertEqual(
            ReminderNotification.command(from: ["show", "--body", "Ready", "--title", "Throwntom"]),
            .show(title: "Throwntom", body: "Ready"))
    }

    func testParsesClear() {
        XCTAssertEqual(ReminderNotification.command(from: ["clear"]), .clear)
    }

    func testRejectsIncompleteOrUnknownArguments() {
        XCTAssertNil(ReminderNotification.command(from: []))
        XCTAssertNil(ReminderNotification.command(from: ["show"]))
        XCTAssertNil(ReminderNotification.command(from: ["show", "--title", "Throwntom"]))
        XCTAssertNil(ReminderNotification.command(from: ["show", "--title", "Throwntom", "--body"]))
        XCTAssertNil(ReminderNotification.command(from: ["show", "--nope", "x", "--title", "t", "--body", "b"]))
        XCTAssertNil(ReminderNotification.command(from: ["bogus"]))
        XCTAssertNil(ReminderNotification.command(from: ["clear", "extra"]))
    }

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

/// Records what each action puts on the wire. Reaching awaiting-confirm against a
/// real daemon would take a whole work period, so the request itself is the seam.
private final class RecordingTransport: DaemonTransport, @unchecked Sendable {
    struct Call: Equatable {
        var method: String
        var path: String
        var body: Data?
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.withLock { _calls } }

    func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
        lock.withLock { _calls.append(Call(method: method, path: path, body: body)) }
        return HTTPResponse(status: 200, headers: [:], body: Data())
    }

    func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish(throwing: DaemonError.transport("no events")) }
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

        XCTAssertEqual(transport.calls.map(\.method), ["POST"])
        XCTAssertEqual(transport.calls.map(\.path), ["/v1/timer/confirm"])
        XCTAssertNil(transport.calls.first?.body)
    }

    func testSnoozePostsTheDefaultSnoozeMinutes() async throws {
        let transport = RecordingTransport()
        try await ReminderNotification.answer(.snooze, using: client(transport))

        XCTAssertEqual(transport.calls.map(\.path), ["/v1/timer/snooze"])
        let body = try XCTUnwrap(transport.calls.first?.body)
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Int]
        XCTAssertEqual(decoded, ["minutes": TimerActions.defaultSnoozeMinutes])
    }
}

import ThrowntomClient
import UserNotifications
import XCTest
@testable import ThrowntomUI

// MARK: - LogRecorder

/// Captures what the app would have written to the unified log. The sink is the only way to see
/// that a catch site recorded anything: `os.Logger` writes where a test process cannot read back.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class LogRecorder: @unchecked Sendable {

  // MARK: Lifecycle

  init() {
    previous = ClientLog.sink
    ClientLog.sink = { [self] entry in
      lock.withLock { recorded.append(entry) }
    }
  }

  deinit {
    ClientLog.sink = previous
  }

  // MARK: Internal

  var entries: [ClientLog.Entry] {
    lock.withLock { recorded }
  }

  var messages: [String] {
    entries.map(\.message)
  }

  // MARK: Private

  private let previous: @Sendable (ClientLog.Entry) -> Void
  private let lock = NSLock()
  private var recorded = [ClientLog.Entry]()

}

// MARK: - UILoggingSitesTests

/// Every place a view or dispatcher catches a failure and shows a fixed sentence, a beep or
/// nothing at all. The user-facing behaviour is unchanged; the error now leaves a record
/// (throwntom-zas).
@MainActor
final class UILoggingSitesTests: XCTestCase {

  func testARefusedTimerActionIsRecordedAndStillBeeps() async throws {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar())

    DaemonDispatch.perform(TimerAction.pause, on: client)
    try await waitUntil { !recorder.messages.isEmpty }

    XCTAssertEqual(recorder.entries.first?.area, .daemon)
    XCTAssertTrue(recorder.messages.contains("send a timer action failed: http 409"), "\(recorder.messages)")
  }

  func testARefusedSnoozeRequestIsRecorded() async throws {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar())

    DaemonDispatch.perform(SnoozeRequest.snooze(minutes: 5), on: client)
    try await waitUntil { !recorder.messages.isEmpty }

    XCTAssertTrue(recorder.messages.contains("send a snooze request failed: http 409"), "\(recorder.messages)")
  }

  /// The command line is what the user typed, so it is the one thing that must not reach the log,
  /// and the daemon quotes it straight back in its refusal (internal/core/core.go's
  /// "unknown command: %s"). The entry names the operation and the status, and nothing else.
  func testARefusedCommandIsRecordedWithoutTheLineTheUserTyped() async throws {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar())

    DaemonDispatch.send("task add buy oat milk for Ada", to: client)
    try await waitUntil { !recorder.messages.isEmpty }

    XCTAssertTrue(recorder.messages.contains("send a command failed: http 409"), "\(recorder.messages)")
    for message in recorder.messages {
      XCTAssertFalse(message.contains("oat milk"), message)
      XCTAssertFalse(message.contains("Ada"), message)
      XCTAssertFalse(message.contains("task add"), message)
    }
  }

  /// Work the app cancelled is not a press that failed, so it neither sounds nor records. No bead
  /// named this one: it followed from routing the beep and the log through one place.
  func testACancelledDispatchNeitherRecordsNorBeeps() async {
    let recorder = LogRecorder()
    let client = DaemonClient(transport: StallingTransport(), registrar: RecordingRegistrar())

    let inFlight = Task { @MainActor in
      do {
        try await client.perform(TimerAction.pause)
      } catch {
        DaemonDispatch.report("send a timer action", error)
      }
    }
    inFlight.cancel()
    await inFlight.value

    XCTAssertEqual(recorder.entries, [])
  }

  func testARefusedLoginItemChangeIsRecorded() {
    let recorder = LogRecorder()

    let setting = LoginItemSetting.afterSetting(
      true,
      in: RefusingLoginItemRegistrar(),
      current: LoginItemSetting(isOn: false, message: nil),
    )

    XCTAssertEqual(setting.message, "Login item: macOS refused the change.")
    XCTAssertEqual(recorder.entries.first?.area, .service)
    XCTAssertEqual(recorder.messages, ["set the login item failed: SMAppServiceErrorDomain 1"])
  }

  func testAReminderMacOSWillNotPostIsRecorded() async {
    let recorder = LogRecorder()
    let presenter = StubReminderPresenter()
    presenter.refusal = NSError(domain: UNErrorDomain, code: 1)
    let responder = ReminderResponder(
      client: DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar()),
      authorizer: StubAuthorizer(status: .authorized, granted: true),
      presenter: presenter,
    )

    await responder.present(
      makeState(phase: .awaitingConfirm, nextStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    )

    XCTAssertFalse(responder.authorization.willDeliver)
    XCTAssertEqual(recorder.entries.first?.area, .reminders)
    XCTAssertEqual(recorder.messages, ["post a reminder failed: UNErrorDomain 1"])
  }

  func testAMorningReminderMacOSWillNotPostIsRecorded() async {
    let recorder = LogRecorder()
    let presenter = StubReminderPresenter()
    presenter.refusal = NSError(domain: UNErrorDomain, code: 1)
    let responder = ReminderResponder(
      client: DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar()),
      authorizer: StubAuthorizer(status: .authorized, granted: true),
      presenter: presenter,
    )

    await responder.present(makeState(phase: .idle, morningPending: true))

    XCTAssertFalse(responder.authorization.willDeliver)
    XCTAssertEqual(recorder.messages, ["post a morning reminder failed: UNErrorDomain 1"])
  }

  /// A banner button is pressed with the window closed, so the caption the client already carries
  /// may never be read. What the daemon refused is recorded where it can be found later.
  func testARefusedReminderAnswerIsRecorded() async throws {
    let client = DaemonClient(transport: StreamingButRefusingTransport(), registrar: RecordingRegistrar())
    client.start()
    defer { client.stop() }
    try await waitUntil { client.serviceStatus.offersDaemonCommands }

    let recorder = LogRecorder()
    let responder = ReminderResponder(
      client: client,
      authorizer: StubAuthorizer(status: .authorized, granted: true),
      presenter: StubReminderPresenter(),
    )
    let answered = expectation(description: "macOS is told the press was handled")
    responder.respond(to: ReminderNotification.Action.confirm.rawValue) { answered.fulfill() }
    await fulfillment(of: [answered], timeout: 5)

    XCTAssertEqual(recorder.entries.first?.area, .reminders)
    XCTAssertTrue(
      recorder.messages.contains("answer a reminder failed: http 409"),
      "\(recorder.messages)",
    )
  }

  func testARefusedAuthorizationRequestIsRecorded() async {
    let recorder = LogRecorder()
    let responder = ReminderResponder(
      client: DaemonClient(transport: RefusingUITransport(), registrar: RecordingRegistrar()),
      authorizer: StubAuthorizer(refusal: NSError(domain: UNErrorDomain, code: 1)),
      presenter: StubReminderPresenter(),
    )

    await responder.requestAuthorization()

    XCTAssertFalse(responder.authorization.willDeliver)
    XCTAssertEqual(recorder.entries.first?.area, .reminders)
    XCTAssertEqual(recorder.messages, ["request notification authorization failed: UNErrorDomain 1"])
  }

  func testAFailedStatsFetchIsRecorded() async {
    let recorder = LogRecorder()
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())

    await StatsLoader().load(from: environment.client)

    XCTAssertEqual(recorder.entries.first?.area, .stats)
    XCTAssertEqual(recorder.messages, ["load the stats failed: transport: no daemon"])
  }

  /// The draft is user text of the plainest kind, and the refusal is about the draft, so this is
  /// where logging the error itself would leak it. The entry names the grammar rule that refused.
  func testARefusedDraftIsRecordedWithoutTheDraft() {
    let recorder = LogRecorder()
    let model = TaskWindowModel()
    model.beginNewTask()
    model.draft = "call Ada about the oat milk\u{7}"

    XCTAssertEqual(NewTaskRow(model: model, onCommit: { _ in }, alert: { }).commit(), .refused)

    XCTAssertEqual(recorder.entries.first?.area, .tasks)
    let message = recorder.messages.first ?? ""
    XCTAssertTrue(message.hasPrefix("commit the new task failed: "), message)
    XCTAssertTrue(message.contains("TaskCommandError"), message)
    for logged in recorder.messages {
      XCTAssertFalse(logged.contains("Ada"), logged)
      XCTAssertFalse(logged.contains("oat milk"), logged)
    }
  }

}

// MARK: - RefusingUITransport

/// A transport that answers every request with the daemon's own 409 refusal, and never opens an
/// event stream, so nothing in the reconnect loop writes into a test's recorder.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class RefusingUITransport: DaemonTransport, @unchecked Sendable {

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 409, headers: [:], body: Data(#"{"error":"no such thing"}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { _ in }
  }

}

// MARK: - StreamingButRefusingTransport

/// A daemon that is plainly up — it sends one state frame and holds the stream open — and refuses
/// every command. That pairing is what a reminder button pressed against a running timer meets
/// when the daemon will not do what the button says.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class StreamingButRefusingTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 409, headers: [:], body: Data(#"{"error":"no such thing"}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    let frame = Self.runningFrame
    return AsyncThrowingStream { continuation in
      continuation.yield(frame)
    }
  }

  // MARK: Private

  /// One frame of a timer that is plainly running. Encoded once, so `events` cannot throw.
  private static let runningFrame = (try? daemonEncoder.encode(makeState(phase: .work))) ?? Data()

}

// MARK: - RefusingLoginItemRegistrar

/// A Login Items stand-in that refuses every change the way `SMAppService` does.
private struct RefusingLoginItemRegistrar: LoginItemRegistrar {
  var loginItemEnabled = false

  func setLoginItem(_: Bool) throws {
    throw NSError(domain: "SMAppServiceErrorDomain", code: 1)
  }
}

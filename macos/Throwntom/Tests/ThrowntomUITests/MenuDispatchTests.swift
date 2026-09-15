import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - MenuDispatchTests

/// What choosing a menu item, a toolbar button or the inline editor sends to the daemon.
@MainActor
final class MenuDispatchTests: XCTestCase {

  // MARK: Internal

  func testTimerItemPostsTheDaemonVerb() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)

    menus.perform(.start)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands, [StubTransport.Request(method: "POST", path: "/v1/timer/start", body: "")])
  }

  func testNewTaskItemOpensTheInlineEditorInsteadOfSending() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)

    menus.run(.newTask)

    XCTAssertTrue(menus.environment.model.isEditing)
    try await settle()
    XCTAssertTrue(transport.commands.isEmpty)
  }

  func testTaskItemSendsTheCommandForTheSelectedTask() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)
    menus.environment.model.sync(
      tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []),
      focusedTaskIDs: [],
    )
    menus.environment.model.selectedID = 8

    menus.run(.complete)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/command", body: #"{"line":"task done 2"}"#)],
    )
  }

  func testTaskItemSendsNothingWithoutASelection() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)

    menus.run(.delete)

    try await settle()
    XCTAssertTrue(transport.commands.isEmpty)
  }

  func testSnoozePostsItsDefaultMinutes() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)

    DaemonDispatch.perform(.snooze, on: environment.client)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":10}"#)],
    )
  }

  func testDaemonDispatchSendsTheLineTheInlineEditorCommits() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)

    DaemonDispatch.send("task add write it down", to: environment.client)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(
        method: "POST",
        path: "/v1/command",
        body: #"{"line":"task add write it down"}"#,
      )],
    )
  }

  /// A duration chosen from the snooze submenu goes straight to the daemon: only `Custom…` has a
  /// question to ask first.
  func testAChosenSnoozeDurationIsPostedRatherThanOpeningTheField() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)

    menus.snooze(.snooze(minutes: 15))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":15}"#)],
    )
    XCTAssertFalse(menus.environment.windowModel.isEnteringSnooze)
  }

  func testAChosenLunchLengthIsPostedRatherThanOpeningTheField() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)

    menus.lunch(.start(minutes: 60))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/timer/lunch", body: #"{"minutes":60}"#)],
    )
    XCTAssertFalse(menus.environment.windowModel.isEnteringLunch)
  }

  /// The one menu verb that drives launchd rather than the socket. The agent is a recorder: the
  /// live one would boot out the daemon of the machine running the tests.
  func testAServiceVerbDrivesTheAgentBehindTheService() async throws {
    let transport = try StubTransport(states: [])
    let environment = makeEnvironment(transport: transport, agent: agent)
    let menus = AppMenus(environment: environment)

    menus.control(.stop)

    try await waitUntil { environment.client.serviceStatus == .stopped }
    XCTAssertEqual(agent.calls, [.unregister])
    XCTAssertTrue(transport.commands.isEmpty, "a service verb is not a command for the daemon")
  }

  func testViewItemTogglesThePanel() throws {
    let menus = try makeMenus(try StubTransport(states: []))
    menus.show(.tasks)
    XCTAssertEqual(menus.environment.windowModel.panel, .tasks)
    menus.show(.stats)
    XCTAssertEqual(menus.environment.windowModel.panel, .stats)
    menus.show(.shortcuts)
    XCTAssertTrue(menus.environment.windowModel.showsShortcuts)
  }

  // MARK: Private

  private let agent = RecordingAgentService()

  private func makeMenus(_ transport: StubTransport) throws -> AppMenus {
    let environment = AppEnvironment(transport: transport)
    return AppMenus(environment: environment)
  }

  /// Gives the detached Task a menu action spawns time to reach the transport.
  private func settle() async throws {
    try await Task.sleep(for: .milliseconds(50))
  }

}

// MARK: - MenuEntryWindowTests

/// What `Custom…` does from the menu bar: it asks the user rather than the daemon, so it opens
/// the window's own duration field and puts the window in front of them.
///
/// The window is the half with no value to assert on. `openWindow` is a SwiftUI environment
/// action, and outside the app lifecycle it does nothing except file a runtime issue saying so —
/// the only trace the call leaves in a test process. That issue is captured here rather than left
/// to print: it is expected, so it belongs in an assertion instead of in the test log. XCTest
/// files each distinct issue once per test case, which is why the two verbs have a test each
/// rather than sharing one.
@MainActor
final class MenuEntryWindowTests: XCTestCase {

  // MARK: Internal

  override func setUp() {
    super.setUp()
    Self.issues.reset()
  }

  nonisolated override func record(_ issue: XCTIssue) {
    guard Self.expectedNotes.contains(issue.compactDescription) else {
      return super.record(issue)
    }
    Self.issues.append(issue.compactDescription)
  }

  func testChoosingACustomSnoozeDurationOpensTheDurationFieldInTheWindow() async throws {
    let transport = try StubTransport(states: [])
    let menus = AppMenus(environment: AppEnvironment(transport: transport))

    menus.snooze(.custom)

    XCTAssertTrue(menus.environment.windowModel.isEnteringSnooze)
    XCTAssertFalse(menus.environment.windowModel.isEnteringLunch, "one field opens at a time")
    try await waitUntil { Self.issues.notes.contains(Self.openWindowNote) }
    XCTAssertTrue(transport.commands.isEmpty, "there is nothing to send until a duration is typed")
  }

  func testChoosingACustomLunchLengthOpensTheLengthFieldInTheWindow() async throws {
    let transport = try StubTransport(states: [])
    let menus = AppMenus(environment: AppEnvironment(transport: transport))

    menus.lunch(.custom)

    XCTAssertTrue(menus.environment.windowModel.isEnteringLunch)
    XCTAssertFalse(menus.environment.windowModel.isEnteringSnooze, "one field opens at a time")
    try await waitUntil { Self.issues.notes.contains(Self.openWindowNote) }
    XCTAssertTrue(transport.commands.isEmpty, "there is nothing to send until a length is typed")
  }

  // MARK: Private

  /// What SwiftUI files when `openWindow` is called with no app lifecycle around it.
  private static let openWindowNote = "Use of OpenWindowAction requires the SwiftUI App Lifecycle."

  /// Both notes one `openWindow(id:)` files: reading the environment action outside a view, and
  /// then using it. Anything else XCTest hands `record(_:)` is a real failure and is passed on.
  private static let expectedNotes = [
    openWindowNote,
    "Accessing Environment<<private>>'s value outside of being installed on a View. "
      + "This will always read the default value and will not update.",
  ]

  private static let issues = IssueLog()

}

// MARK: - IssueLog

/// The runtime issues a test expected, kept where `record(_:)` can reach them: XCTest may call it
/// from any thread, and the tests that read it are on the main actor.
// `recorded` is only touched under `lock`.
// swiftlint:disable:next no_unchecked_sendable
private final class IssueLog: @unchecked Sendable {

  // MARK: Internal

  var notes: [String] {
    lock.withLock { recorded }
  }

  func append(_ note: String) {
    lock.withLock { recorded.append(note) }
  }

  func reset() {
    lock.withLock { recorded.removeAll() }
  }

  // MARK: Private

  private let lock = NSLock()
  private var recorded = [String]()

}

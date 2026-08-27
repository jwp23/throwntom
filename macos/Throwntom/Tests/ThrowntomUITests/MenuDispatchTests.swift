import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What choosing a menu item, a toolbar button or the inline editor sends to the daemon.
@MainActor
final class MenuDispatchTests: XCTestCase {
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

        XCTAssertTrue(menus.model.isEditing)
        try await settle()
        XCTAssertTrue(transport.commands.isEmpty)
    }

    func testTaskItemSendsTheCommandForTheSelectedTask() async throws {
        let transport = try StubTransport(states: [])
        let menus = try makeMenus(transport)
        menus.model.sync(
            tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []), focusedTaskIDs: [])
        menus.model.selectedID = 8

        menus.run(.complete)

        try await waitUntil { !transport.commands.isEmpty }
        XCTAssertEqual(
            transport.commands,
            [StubTransport.Request(method: "POST", path: "/v1/command", body: #"{"line":"task done 2"}"#)])
    }

    func testTaskItemSendsNothingWithoutASelection() async throws {
        let transport = try StubTransport(states: [])
        let menus = try makeMenus(transport)

        menus.run(.delete)

        try await settle()
        XCTAssertTrue(transport.commands.isEmpty)
    }

    func testTimerActionButtonPostsSnoozeWithItsDefaultMinutes() async throws {
        let transport = try StubTransport(states: [])
        let environment = AppEnvironment(transport: transport)

        await TimerActionButton(action: .snooze, client: environment.client).perform()

        XCTAssertEqual(
            transport.commands,
            [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":10}"#)])
    }

    func testTaskWindowSendsTheLineTheInlineEditorCommits() async throws {
        let transport = try StubTransport(states: [])
        let environment = AppEnvironment(transport: transport)

        TaskWindow(client: environment.client, model: environment.model).send("task add write it down")

        try await waitUntil { !transport.commands.isEmpty }
        XCTAssertEqual(
            transport.commands,
            [StubTransport.Request(
                method: "POST", path: "/v1/command", body: #"{"line":"task add write it down"}"#)])
    }

    private func makeMenus(_ transport: StubTransport) throws -> AppMenus {
        let environment = AppEnvironment(transport: transport)
        return AppMenus(client: environment.client, model: environment.model)
    }

    /// Gives the detached Task a menu action spawns time to reach the transport.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }
}

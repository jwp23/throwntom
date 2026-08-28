import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// How the task window feeds daemon state into the model the list and menus read from.
@MainActor
final class TaskWindowSyncTests: XCTestCase {
  func testTheWindowPushesTheDaemonsTasksAndFocusIntoTheModel() async throws {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5)], completed: [makeTask(id: 6, done: true)])
    let environment = AppEnvironment(
      transport: try StubTransport(states: [makeState(phase: .work, focusedTaskIds: [5])], tasks: tasks)
    )
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil && !environment.client.tasks.active.isEmpty }

    TaskWindow(client: environment.client, model: environment.model).syncModel()

    XCTAssertEqual(environment.model.tasks.active.map(\.id), [4, 5])
    XCTAssertEqual(environment.model.tasks.completed.map(\.id), [6])
    XCTAssertEqual(environment.model.focusedIDs, [5])
  }

  func testNothingIsFocusedUntilTheDaemonSaysSo() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))

    TaskWindow(client: environment.client, model: environment.model).syncModel()

    XCTAssertTrue(environment.model.tasks.active.isEmpty)
    XCTAssertTrue(environment.model.focusedIDs.isEmpty)
  }
}

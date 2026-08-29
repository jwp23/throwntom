import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class TaskContextMenuTests: XCTestCase {
  func testHintLineIsBuiltFromTaskActionHints() {
    XCTAssertEqual(TaskHints.line, "⌘N new · ⌘⏎ done · ⌘F focus · ⌥↑↓ move · ⌘⌫ delete")
  }

  func testChoosingAnItemActsOnThatRowNotTheSelection() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    environment.model.sync(tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []), focusedTaskIDs: [])
    environment.model.selectedID = 7
    let menu = TaskContextMenu(task: makeTask(id: 8), environment: environment)
    menu.run(.complete)
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.first?.body, #"{"line":"task done 2"}"#)
    XCTAssertEqual(environment.model.selectedID, 8)
  }

  func testNewTaskFromTheMenuOpensTheEditor() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let menu = TaskContextMenu(task: makeTask(id: 1), environment: environment)
    menu.run(.newTask)
    XCTAssertTrue(environment.model.isEditing)
    _ = menu.body
  }
}

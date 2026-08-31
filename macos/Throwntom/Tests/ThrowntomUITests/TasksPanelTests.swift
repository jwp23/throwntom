import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class TasksPanelTests: XCTestCase {

  // MARK: Internal

  /// A finished task differs from an outstanding one by a line through it and nothing else, and a
  /// line through text is silent. Found while auditing the window for what it says only in ink;
  /// no bead covered it.
  func testARowSaysInWordsWhatItOtherwiseOnlyDraws() {
    XCTAssertEqual(TaskRow(task: makeTask(id: 1, description: "write"), focused: false).label, "write")
    XCTAssertEqual(TaskRow(task: makeTask(id: 2, description: "write"), focused: true).label, "write, focused")
    XCTAssertEqual(
      TaskRow(task: makeTask(id: 3, description: "write", done: true), focused: false).label,
      "write, completed",
    )
  }

  func testEmptyStateNamesTheShortcutThatAddsATask() {
    XCTAssertEqual(TaskHints.empty, "No tasks — ⌘N to add one")
  }

  func testPlaceholderStandsInForAnEmptyList() throws {
    let panel = try makePanel()

    XCTAssertTrue(panel.showsEmptyState, "nothing to list yet")

    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    XCTAssertFalse(panel.showsEmptyState)

    panel.model.sync(tasks: TaskList(active: [], completed: [makeTask(id: 2, done: true)]), focusedTaskIDs: [])
    XCTAssertFalse(panel.showsEmptyState, "a completed task is still a task")
  }

  func testOpeningTheEditorReplacesThePlaceholderWithTheRow() throws {
    let panel = try makePanel()
    panel.model.beginNewTask()

    XCTAssertFalse(panel.showsEmptyState)
  }

  func testPanelBodyBuildsEmptyAndPopulated() throws {
    let panel = try makePanel()
    _ = panel.body
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: [makeTask(id: 2, done: true)]), focusedTaskIDs: [1])
    _ = panel.body
  }

  // MARK: Private

  private func makePanel() throws -> TasksPanel {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return TasksPanel(environment: environment, scheme: Palette.scheme(for: .work))
  }

}

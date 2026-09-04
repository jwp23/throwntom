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
    XCTAssertEqual(makeRow(id: 1, description: "write", focused: false).label, "write")
    XCTAssertEqual(makeRow(id: 2, description: "write", focused: true).label, "write, focused")
    XCTAssertEqual(makeRow(id: 3, description: "write", done: true, focused: false).label, "write, completed")
  }

  /// The panel's hint is the one place a reader who has never opened a context menu learns that
  /// ⌘F is a toggle, so it has to word itself for the row the key would act on.
  func testTheHintNamesUnfocusWhenTheSelectedRowIsFocused() throws {
    let panel = try makePanel()
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])

    panel.model.selectedID = 1
    XCTAssertEqual(panel.hintLine, TaskHints.line(focused: false))

    panel.model.selectedID = 2
    XCTAssertEqual(panel.hintLine, TaskHints.line(focused: true))
  }

  /// The rows sit on the panel, so their star takes the panel's text colour rather than a tint of
  /// its own; `PaletteTests` is what holds that colour to 4.5:1.
  func testTheRowMarkTakesThePanelsOwnTextColour() throws {
    let scheme = Palette.scheme(for: .idle)
    let panel = TasksPanel(environment: AppEnvironment(transport: try StubTransport(states: [])), scheme: scheme)
    XCTAssertEqual(panel.markColor, scheme.panelTaskMark)
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

  private func makeRow(id: Int, description: String = "task", done: Bool = false, focused: Bool) -> TaskRow {
    TaskRow(
      task: makeTask(id: id, description: description, done: done),
      focused: focused,
      markColor: Palette.scheme(for: .work).panelTaskMark,
    )
  }

  private func makePanel() throws -> TasksPanel {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return TasksPanel(environment: environment, scheme: Palette.scheme(for: .work))
  }

}

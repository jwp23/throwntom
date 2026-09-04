import XCTest
@testable import ThrowntomClient

final class TaskCommandsTests: XCTestCase {

  // MARK: Internal

  func testAddTaskNormalisesWhitespace() throws {
    XCTAssertEqual(try TaskCommands.addTask("  write   the  plan "), "task add write the plan")
  }

  func testAddTaskRejectsEmptyAndControlCharacters() {
    XCTAssertThrowsError(try TaskCommands.addTask("   ")) { XCTAssertEqual($0 as? TaskCommandError, .emptyDescription) }
    XCTAssertThrowsError(try TaskCommands.addTask("a\nb")) { XCTAssertEqual($0 as? TaskCommandError, .controlCharacters) }
  }

  func testPositionIsOneBasedWithinActiveList() {
    let list = TaskList(active: [item(7), item(3), item(9)], completed: [item(1)])
    XCTAssertEqual(TaskCommands.position(of: 3, in: list), 2)
    XCTAssertEqual(TaskCommands.position(of: 9, in: list), 3)
    XCTAssertNil(TaskCommands.position(of: 1, in: list), "completed tasks have no position")
    XCTAssertNil(TaskCommands.position(of: 42, in: list))
  }

  func testLinesForEachAction() {
    XCTAssertEqual(TaskCommands.line(for: .complete, position: 2, focused: false), "task done 2")
    XCTAssertEqual(TaskCommands.line(for: .delete, position: 2, focused: false), "task remove 2")
    XCTAssertEqual(TaskCommands.line(for: .focus, position: 2, focused: false), "task focus 2")
    XCTAssertEqual(TaskCommands.line(for: .focus, position: 2, focused: true), "task unfocus 2")
    XCTAssertEqual(TaskCommands.line(for: .moveUp, position: 2, focused: false), "task up 2")
    XCTAssertEqual(TaskCommands.line(for: .moveDown, position: 2, focused: false), "task down 2")
  }

  func testTitlesAndHints() {
    XCTAssertEqual(TaskAction.newTask.shortcutHint, "⌘N")
    XCTAssertEqual(TaskAction.complete.shortcutHint, "⌘⏎")
    XCTAssertEqual(TaskAction.delete.shortcutHint, "⌘⌫")
    XCTAssertEqual(TaskAction.focus.shortcutHint, "⌘⇧F")
    XCTAssertEqual(TaskAction.moveUp.shortcutHint, "⌥↑")
    XCTAssertEqual(TaskAction.moveDown.shortcutHint, "⌥↓")
    XCTAssertEqual(TaskAction.newTask.title, "New Task")
    XCTAssertEqual(TaskAction.focus.title, "Focus")
  }

  func testFocusIsTheOnlyVerbWhoseTitleTracksTheTaskState() {
    XCTAssertEqual(TaskAction.focus.title(focused: false), "Focus")
    XCTAssertEqual(TaskAction.focus.title(focused: true), "Unfocus")
    for action in TaskAction.allCases where action != .focus {
      XCTAssertEqual(action.title(focused: true), action.title, "\(action)")
    }
  }

  // MARK: Private

  private func item(_ id: Int) -> TaskItem {
    TaskItem(id: id, description: "t\(id)", done: false, createdAt: Date(), completedAt: Date())
  }

}

import XCTest
@testable import ThrowntomClient

@MainActor
final class TaskWindowModelTests: XCTestCase {
    private func item(_ id: Int) -> TaskItem {
        TaskItem(id: id, description: "t\(id)", done: false, createdAt: Date(), completedAt: Date())
    }

    private func model(ids: [Int], focused: Set<Int> = []) -> TaskWindowModel {
        let m = TaskWindowModel()
        m.sync(tasks: TaskList(active: ids.map(item), completed: [item(99)]), focusedIDs: focused)
        return m
    }

    func testSyncSelectsFirstTaskAndKeepsExistingSelection() {
        let m = model(ids: [5, 6, 7])
        XCTAssertEqual(m.selectedID, 5)
        m.selectedID = 7
        m.sync(tasks: TaskList(active: [item(7), item(5)]), focusedIDs: [])
        XCTAssertEqual(m.selectedID, 7, "selection follows the task, not the row")
        m.sync(tasks: TaskList(active: [item(5)]), focusedIDs: [])
        XCTAssertEqual(m.selectedID, 5, "vanished selection falls back to the first task")
        m.sync(tasks: TaskList(), focusedIDs: [])
        XCTAssertNil(m.selectedID)
    }

    func testMoveSelectionClampsAtEnds() {
        let m = model(ids: [5, 6, 7])
        m.moveSelection(by: 1)
        XCTAssertEqual(m.selectedID, 6)
        m.moveSelection(by: 5)
        XCTAssertEqual(m.selectedID, 7)
        m.moveSelection(by: -1)
        XCTAssertEqual(m.selectedID, 6)
        m.moveSelection(by: -10)
        XCTAssertEqual(m.selectedID, 5)
    }

    func testNewTaskRowLifecycle() throws {
        let m = model(ids: [5])
        XCTAssertFalse(m.isEditing)
        m.beginNewTask()
        XCTAssertTrue(m.isEditing)
        XCTAssertEqual(m.draft, "")
        m.draft = "  ship it "
        XCTAssertEqual(try m.commitNewTask(), "task add ship it")
        XCTAssertFalse(m.isEditing)

        m.beginNewTask()
        m.draft = "   "
        XCTAssertNil(try m.commitNewTask(), "empty draft commits nothing and closes the row")
        XCTAssertFalse(m.isEditing)

        m.beginNewTask()
        m.draft = "abandoned"
        m.cancelEdit()
        XCTAssertFalse(m.isEditing)
        XCTAssertNil(m.draft)
    }

    func testCommandsUseSelectedPositionAndFocusState() {
        let m = model(ids: [5, 6, 7], focused: [6])
        m.selectedID = 6
        XCTAssertEqual(m.command(for: .complete), "task done 2")
        XCTAssertEqual(m.command(for: .delete), "task remove 2")
        XCTAssertEqual(m.command(for: .focus), "task unfocus 2")
        XCTAssertEqual(m.command(for: .moveUp), "task up 2")
        XCTAssertEqual(m.command(for: .moveDown), "task down 2")
        m.selectedID = 5
        XCTAssertEqual(m.command(for: .focus), "task focus 1")
        XCTAssertNil(m.command(for: .newTask))
    }

    func testCanPerformNeedsSelectionAndNoOpenEditor() {
        let m = model(ids: [])
        XCTAssertFalse(m.canPerform(.complete))
        XCTAssertTrue(m.canPerform(.newTask))
        let n = model(ids: [5])
        XCTAssertTrue(n.canPerform(.complete))
        n.beginNewTask()
        XCTAssertFalse(n.canPerform(.complete))
        XCTAssertFalse(n.canPerform(.newTask))
        XCTAssertNil(n.command(for: .complete))
    }
}

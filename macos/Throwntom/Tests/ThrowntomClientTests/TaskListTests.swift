import XCTest
@testable import ThrowntomClient

final class TaskListTests: XCTestCase {
    private func item(_ id: Int) -> TaskItem {
        TaskItem(id: id, description: "t\(id)", done: false, createdAt: Date(), completedAt: Date())
    }

    func testFocusedKeepsListOrderAndIgnoresUnknownIDs() {
        let list = TaskList(active: [item(3), item(1), item(2)], completed: [item(9)])
        XCTAssertEqual(list.focused(ids: [2, 3, 42]).map(\.id), [3, 2], "focus follows list order, not id order")
        XCTAssertEqual(list.focused(ids: [9]).map(\.id), [], "completed tasks are never focused")
        XCTAssertEqual(list.focused(ids: []).map(\.id), [])
    }
}

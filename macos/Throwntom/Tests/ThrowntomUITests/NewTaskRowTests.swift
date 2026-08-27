import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What the inline new-task editor does with the text in it. Every outcome closes the row; they
/// differ in what the task window is asked to send.
@MainActor
final class NewTaskRowTests: XCTestCase {
    func testATypedTaskCommitsTheAddCommand() {
        let model = TaskWindowModel()
        model.beginNewTask()
        model.draft = "write the report"

        XCTAssertEqual(makeRow(model).commit(), .send("task add write the report"))
        XCTAssertFalse(model.isEditing)
    }

    func testABlankDraftClosesTheRowWithNothingToSend() {
        let model = TaskWindowModel()
        model.beginNewTask()
        model.draft = "   "

        XCTAssertEqual(makeRow(model).commit(), .nothing)
        XCTAssertFalse(model.isEditing)
    }

    func testTextTheTaskGrammarRefusesClosesTheRow() {
        let model = TaskWindowModel()
        model.beginNewTask()
        model.draft = "bell\u{7}"

        XCTAssertEqual(makeRow(model).commit(), .refused)
        XCTAssertFalse(model.isEditing)
    }

    func testSubmittingATypedTaskHandsTheLineToTheWindow() {
        let model = TaskWindowModel()
        model.beginNewTask()
        model.draft = "write the report"
        var committed: [String] = []

        NewTaskRow(model: model) { committed.append($0) }.submit()

        XCTAssertEqual(committed, ["task add write the report"])
    }

    /// The refusal is the system alert sound, which is why this is the one test in the suite
    /// that makes a noise. What it asserts is that nothing reaches the daemon.
    func testSubmittingTextTheGrammarRefusesSendsNothing() {
        let model = TaskWindowModel()
        model.beginNewTask()
        model.draft = "bell\u{7}"
        var committed: [String] = []

        NewTaskRow(model: model) { committed.append($0) }.submit()

        XCTAssertTrue(committed.isEmpty)
        XCTAssertFalse(model.isEditing)
    }

    func testSubmittingABlankDraftHandsTheWindowNothing() {
        let model = TaskWindowModel()
        model.beginNewTask()
        var committed: [String] = []

        NewTaskRow(model: model) { committed.append($0) }.submit()

        XCTAssertTrue(committed.isEmpty)
    }

    private func makeRow(_ model: TaskWindowModel) -> NewTaskRow {
        NewTaskRow(model: model) { _ in }
    }
}

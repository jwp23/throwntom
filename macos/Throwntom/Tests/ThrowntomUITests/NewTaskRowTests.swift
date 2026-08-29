import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What the inline new-task editor does with the text in it. Every outcome closes the row; they
/// differ in what the tasks panel is asked to send.
@MainActor
final class NewTaskRowTests: XCTestCase {

  // MARK: Internal

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
    var committed = [String]()

    NewTaskRow(model: model) { committed.append($0) }.submit()

    XCTAssertEqual(committed, ["task add write the report"])
  }

  /// Refused text alerts the user and sends nothing. The alert is injected so the suite
  /// stays silent and the alert itself can be asserted rather than merely heard.
  func testSubmittingTextTheGrammarRefusesAlertsAndSendsNothing() {
    let model = TaskWindowModel()
    model.beginNewTask()
    model.draft = "bell\u{7}"
    var committed = [String]()
    var alerts = 0

    var row = NewTaskRow(model: model) { committed.append($0) }
    row.alert = { alerts += 1 }
    row.submit()

    XCTAssertEqual(alerts, 1)
    XCTAssertTrue(committed.isEmpty)
    XCTAssertFalse(model.isEditing)
  }

  func testSubmittingABlankDraftHandsTheWindowNothing() {
    let model = TaskWindowModel()
    model.beginNewTask()
    var committed = [String]()

    NewTaskRow(model: model) { committed.append($0) }.submit()

    XCTAssertTrue(committed.isEmpty)
  }

  // MARK: Private

  private func makeRow(_ model: TaskWindowModel) -> NewTaskRow {
    NewTaskRow(model: model) { _ in }
  }

}

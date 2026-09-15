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

  /// What the body is actually made of: the field, styled, focus-bound, and wired to appear,
  /// change, submit and exit. Named by SwiftUI's own types, the way `MainWindowBodyTests` pins
  /// `MainWindow`.
  func testBodyIsTheFieldStyledFocusedAndWiredToAppearChangeSubmitAndExit() {
    XCTAssertEqual(modifierLayers(of: makeRow(TaskWindowModel()).body).map(shape), [
      "TextFieldStyleModifier<RoundedBorderTextFieldStyle>",
      "FocusStateBindingModifier<Bool>",
      "_AppearanceActionModifier",
      "_ValueActionModifier2<String>",
      "_AppearanceActionModifier",
      "OnSubmitModifier",
      "OnCommandModifier",
    ])
  }

  /// Pressing Return in the field is what actually calls `submit()` — not merely `submit()`
  /// called directly, which every other test in this file does.
  func testSubmittingFromTheFieldSendsTheDraft() throws {
    let model = TaskWindowModel()
    model.beginNewTask()
    model.draft = "write the report"
    var committed = [String]()
    let row = NewTaskRow(model: model) { committed.append($0) }
    let onSubmit = try XCTUnwrap(try child("action", of: try layer(.submit, of: row)) as? () -> Void)

    onSubmit()

    XCTAssertEqual(committed, ["task add write the report"])
  }

  /// Escape is the row's own Cancel command — `MainWindow`'s Escape closes panels, but inside an
  /// open row it is this wiring, not that one, that answers it.
  func testExitCommandCancelsTheDraft() throws {
    let model = TaskWindowModel()
    model.beginNewTask()
    model.draft = "half-typed"
    let row = NewTaskRow(model: model) { _ in }
    let exit = try layer(.exitCommand, of: row)
    let cancel = try XCTUnwrap(
      try child("action", of: try child("action", of: exit)) as? () -> Void,
      "the Cancel command has nothing to run",
    )

    cancel()

    XCTAssertFalse(model.isEditing, "Escape closed the row that was open")
  }

  // MARK: Private

  /// Where each modifier sits in the stack the body hangs off the field, counted from the
  /// innermost. `testBodyIsTheFieldStyledFocusedAndWiredToAppearChangeSubmitAndExit` is what
  /// holds these to the source.
  private enum Layer: Int {
    case textFieldStyle
    case focused
    case appear
    case textChange
    case textChangeAppear
    case submit
    case exitCommand
  }

  private func makeRow(_ model: TaskWindowModel) -> NewTaskRow {
    NewTaskRow(model: model) { _ in }
  }

  private func layer(_ layer: Layer, of row: NewTaskRow) throws -> Any {
    try part(layer.rawValue, of: modifierLayers(of: row.body))
  }

}

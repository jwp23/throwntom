import Foundation
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

@MainActor
final class TaskWindowContentTests: XCTestCase {

  // MARK: Internal

  func testPlaceholderExplainsTheWaitUntilDaemonStateArrives() {
    let connecting = makeContent(state: nil, connection: .connecting)
    let starting = makeContent(state: nil, connection: .startingDaemon)

    XCTAssertEqual(connecting.placeholder, "Throwntom…")
    XCTAssertEqual(starting.placeholder, "Starting timer…")
  }

  func testPlaceholderClearsOnceDaemonStateArrives() {
    let content = makeContent(state: makeState(phase: .work), connection: .connected)

    XCTAssertNil(content.placeholder)
  }

  func testPlaceholderStaysWhileReconnectingWithoutState() {
    let content = makeContent(state: nil, connection: .reconnecting(attempt: 2))

    XCTAssertEqual(content.placeholder, "Throwntom…")
  }

  func testActiveTasksAndFocusComeFromTheModel() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])

    let content = makeContent(state: makeState(), connection: .connected, model: model)

    XCTAssertEqual(content.active.map(\.id), [1, 2])
    XCTAssertEqual(content.focusedIDs, [2])
  }

  func testCompletedSectionIsOmittedWhenNothingIsDone() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])

    XCTAssertNil(makeContent(state: makeState(), connection: .connected, model: model).completed)
  }

  func testCompletedSectionCountsTheFinishedTasks() throws {
    let model = TaskWindowModel()
    let done = [makeTask(id: 8, done: true), makeTask(id: 9, done: true)]
    model.sync(tasks: TaskList(active: [], completed: done), focusedTaskIDs: [])

    let completed = try XCTUnwrap(makeContent(state: makeState(), connection: .connected, model: model).completed)

    XCTAssertEqual(completed.title, "Completed (2)")
    XCTAssertEqual(completed.tasks.map(\.id), [8, 9])
  }

  func testEditingFollowsTheInlineNewTaskRow() {
    let model = TaskWindowModel()
    XCTAssertFalse(makeContent(state: makeState(), connection: .connected, model: model).isEditing)

    model.beginNewTask()

    XCTAssertTrue(makeContent(state: makeState(), connection: .connected, model: model).isEditing)
  }

  func testToolbarOffersTheVerbsTheCurrentPhaseAccepts() {
    let content = makeContent(state: makeState(phase: .awaitingConfirm), connection: .connected)

    XCTAssertEqual(content.toolbarActions, [.confirm, .snooze, .newCycle])
  }

  func testToolbarIsEmptyUntilDaemonStateArrives() {
    XCTAssertTrue(makeContent(state: nil, connection: .connecting).toolbarActions.isEmpty)
  }

  // MARK: Private

  private func makeContent(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    model: TaskWindowModel? = nil,
  ) -> TaskWindowContent {
    TaskWindowContent(state: state, connection: connection, model: model ?? TaskWindowModel(), now: .now)
  }

}

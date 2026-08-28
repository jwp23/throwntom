import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - TimerMenuModelTests

final class TimerMenuModelTests: XCTestCase {

  // MARK: Internal

  func testWithoutDaemonStateEverythingIsDisabled() {
    let menu = MenuModel.timer(state: nil, isEditing: false)

    XCTAssertFalse(menu.items.isEmpty)
    XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
  }

  func testIdleEnablesTheVerbsTheDaemonAccepts() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)

    XCTAssertEqual(enabledActions(menu), [.start, .skipToday, .newCycle])
  }

  func testMorningPendingAlsoEnablesSnooze() {
    let menu = MenuModel.timer(state: makeState(phase: .idle, morningPending: true), isEditing: false)

    XCTAssertEqual(enabledActions(menu), [.start, .snooze, .skipToday, .newCycle])
  }

  func testWorkOffersPauseAndPausedOffersResume() {
    let working = MenuModel.timer(state: makeState(phase: .work), isEditing: false)
    let paused = MenuModel.timer(state: makeState(phase: .paused), isEditing: false)

    XCTAssertEqual(enabledActions(working), [.pause])
    XCTAssertEqual(enabledActions(paused), [.resume])
    XCTAssertTrue(working.items.contains { $0.action == .pause })
    XCTAssertTrue(paused.items.contains { $0.action == .resume })
  }

  func testConfirmYieldsTheReturnKeyToTheNewTaskRow() throws {
    let state = makeState(phase: .awaitingConfirm)
    let idle = MenuModel.timer(state: state, isEditing: false)
    let editing = MenuModel.timer(state: state, isEditing: true)

    XCTAssertTrue(try XCTUnwrap(idle.item(for: .confirm)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(editing.item(for: .confirm)).isEnabled)
  }

  func testEditingDoesNotDisableTheOtherVerbs() {
    let menu = MenuModel.timer(state: makeState(phase: .awaitingConfirm), isEditing: true)

    XCTAssertEqual(enabledActions(menu), [.snooze, .newCycle])
  }

  func testCycleVerbsSitBelowTheirOwnSeparator() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)

    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.last?.map(\.action), [.skipToday, .newCycle])
  }

  func testTimedVerbsCarryTheirShortcutsAndCycleVerbsDoNot() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .start)?.shortcut), MenuShortcut(key: "r", modifiers: .command))
    XCTAssertEqual(try XCTUnwrap(menu.item(for: .snooze)?.shortcut), MenuShortcut(key: "s", modifiers: [.command, .shift]))
    XCTAssertNil(try XCTUnwrap(menu.item(for: .skipToday)).shortcut)
    XCTAssertNil(try XCTUnwrap(menu.item(for: .newCycle)).shortcut)
  }

  func testItemTitlesComeFromTheAction() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .start)).title, TimerAction.start.title)
  }

  // MARK: Private

  private func enabledActions(_ menu: MenuModel<TimerAction>) -> [TimerAction] {
    menu.items.filter(\.isEnabled).map(\.action)
  }

}

// MARK: - TaskMenuModelTests

@MainActor
final class TaskMenuModelTests: XCTestCase {

  // MARK: Internal

  func testWithoutTasksOnlyNewTaskIsEnabled() {
    let menu = MenuModel.tasks(model: TaskWindowModel())

    XCTAssertEqual(enabledActions(menu), [.newTask])
  }

  func testSelectingATaskEnablesEveryVerb() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])

    XCTAssertEqual(enabledActions(MenuModel.tasks(model: model)), TaskAction.allCases)
  }

  func testEditingDisablesEveryVerb() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    model.beginNewTask()

    XCTAssertTrue(MenuModel.tasks(model: model).items.allSatisfy { !$0.isEnabled })
  }

  func testReorderingVerbsSitBelowTheirOwnSeparator() {
    let menu = MenuModel.tasks(model: TaskWindowModel())

    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.first?.map(\.action), [.newTask, .complete, .delete, .focus])
    XCTAssertEqual(menu.groups.last?.map(\.action), [.moveUp, .moveDown])
  }

  func testEveryTaskVerbKeepsAShortcut() {
    let menu = MenuModel.tasks(model: TaskWindowModel())

    XCTAssertTrue(menu.items.allSatisfy { $0.shortcut != nil })
  }

  // MARK: Private

  private func enabledActions(_ menu: MenuModel<TaskAction>) -> [TaskAction] {
    menu.items.filter(\.isEnabled).map(\.action)
  }

}

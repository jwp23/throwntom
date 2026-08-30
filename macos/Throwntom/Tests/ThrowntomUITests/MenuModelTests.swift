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

    XCTAssertEqual(enabledActions(working), [.pause, .skipToday])
    XCTAssertEqual(enabledActions(paused), [.resume, .skipToday])
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

    XCTAssertEqual(enabledActions(menu), [.snooze, .skipToday, .newCycle])
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

  func testFocusReadsUnfocusWhenTheSelectedTaskIsFocused() throws {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])

    model.selectedID = 1
    XCTAssertEqual(try XCTUnwrap(MenuModel.tasks(model: model).item(for: .focus)).title, "Focus")

    model.selectedID = 2
    XCTAssertEqual(try XCTUnwrap(MenuModel.tasks(model: model).item(for: .focus)).title, "Unfocus")
  }

  func testARowOverridesTheSelectionsFocusState() throws {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])
    model.selectedID = 1

    let menu = MenuModel.tasks(model: model, focusedRow: true)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .focus)).title, "Unfocus")
  }

  func testOtherVerbsKeepTheirTitleWhateverTheFocusState() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [1])

    XCTAssertEqual(MenuModel.tasks(model: model).item(for: .complete)?.title, TaskAction.complete.title)
  }

  // MARK: Private

  private func enabledActions(_ menu: MenuModel<TaskAction>) -> [TaskAction] {
    menu.items.filter(\.isEnabled).map(\.action)
  }

}

// MARK: - ViewMenuModelTests

@MainActor
final class ViewMenuModelTests: XCTestCase {

  func testViewMenuListsPanelsAndShortcutSheet() throws {
    let model = WindowModel()
    let menu = MenuModel.view(model: model)
    XCTAssertEqual(menu.items.map(\.title), ["Tasks", "Stats", "Keyboard Shortcuts"])
    XCTAssertEqual(menu.item(for: .tasks)?.shortcut, MenuShortcut(key: "t", modifiers: .command))
    XCTAssertEqual(menu.item(for: .stats)?.shortcut, MenuShortcut(key: "i", modifiers: [.command, .shift]))
    XCTAssertEqual(menu.item(for: .shortcuts)?.shortcut, MenuShortcut(key: "/", modifiers: .command))
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
    model.showsShortcuts = true
    XCTAssertFalse(try XCTUnwrap(MenuModel.view(model: model).item(for: .shortcuts)?.isEnabled))
  }

  func testViewActionHintsMatchShortcuts() {
    XCTAssertEqual(ViewAction.allCases.map(\.shortcutHint), ["⌘T", "⌘⇧I", "⌘/", "⌘,"])
  }

  func testOpenConfigBelongsToTheAppMenuNotTheViewMenu() {
    let menu = MenuModel.view(model: WindowModel())

    XCTAssertFalse(menu.items.contains { $0.action == .openConfig }, "the View menu keeps its three items")
    XCTAssertEqual(MenuModel.appConfig().items.map(\.title), ["Open Config File…"])
    XCTAssertEqual(MenuModel.appConfig().item(for: .openConfig)?.shortcut, MenuShortcut(key: ",", modifiers: .command))
    XCTAssertNil(ViewAction.openConfig.panel)
  }

  func testWindowCommandsAreTheViewMenuPlusTheConfigFile() {
    let menu = MenuModel.windowCommands(model: WindowModel())

    XCTAssertEqual(menu.groups.count, 1, "a chip row draws no separators")
    XCTAssertEqual(menu.items.map(\.action), [.tasks, .stats, .shortcuts, .openConfig])
    XCTAssertEqual(menu.items.map(\.title), ["Tasks", "Stats", "Keyboard Shortcuts", "Open Config File…"])
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

}

// MARK: - MenuGroupsTests

@MainActor
final class MenuGroupsTests: XCTestCase {

  func testBodyBuilds() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)
    _ = MenuGroups(menu: menu) { item in Text(item.title) }.body
  }

  func testFirstGroupHasNoLeadingDivider() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }
    _ = groups.groupView(index: 0, group: menu.groups[0])
  }

  func testLaterGroupsGetADivider() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), isEditing: false)
    XCTAssertGreaterThan(menu.groups.count, 1, "the divider branch needs a second group to exercise")
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }
    _ = groups.groupView(index: 1, group: menu.groups[1])
  }

}

// MARK: - ServiceMenuModelTests

/// The Timer menu's service group: one toggle whose title says what pressing it does, so the
/// menu bar carries Start and Stop exactly as the window does (ADR-006).
final class ServiceMenuModelTests: XCTestCase {
  func testRunningServiceOffersStop() {
    let menu = MenuModel.service(connection: .connected, registrationFailed: false)

    XCTAssertEqual(menu.items.map(\.title), ["Stop Timer Service"])
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

  func testStoppedServiceOffersStart() {
    let menu = MenuModel.service(connection: .stopped, registrationFailed: false)

    XCTAssertEqual(menu.items.map(\.title), ["Start Timer Service"])
  }

  func testRefusedLaunchOffersStartRatherThanARetryOfItsOwn() {
    let menu = MenuModel.service(connection: .startingDaemon, registrationFailed: true)

    XCTAssertEqual(menu.items.map(\.title), ["Start Timer Service"])
  }

  /// Stopping the service is deliberate and heavy, so it claims no key: a stray keystroke must
  /// not be able to take the timer down.
  func testTheServiceToggleBindsNoKey() {
    XCTAssertNil(MenuModel.service(connection: .connected, registrationFailed: false).items.first?.shortcut)
  }
}

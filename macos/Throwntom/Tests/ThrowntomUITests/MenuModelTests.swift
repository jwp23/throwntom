import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - TimerMenuModelTests

final class TimerMenuModelTests: XCTestCase {

  // MARK: Internal

  func testWithoutDaemonStateEverythingIsDisabled() {
    let menu = MenuModel.timer(state: nil, returnIsTaken: false, daemonAvailable: true)

    XCTAssertFalse(menu.items.isEmpty)
    XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
  }

  func testIdleEnablesTheVerbsTheDaemonAccepts() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(enabledActions(menu), [.start, .skipToday, .newCycle, .lunch, .meeting])
  }

  func testMorningPendingAlsoEnablesSnooze() {
    let menu = MenuModel.timer(state: makeState(phase: .idle, morningPending: true), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(enabledActions(menu), [.start, .snooze, .skipToday, .newCycle, .lunch, .meeting])
  }

  func testWorkOffersPauseAndPausedOffersResume() {
    let working = MenuModel.timer(state: makeState(phase: .work), returnIsTaken: false, daemonAvailable: true)
    let paused = MenuModel.timer(state: makeState(phase: .paused), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(enabledActions(working), [.pause, .skip, .skipToday, .lunch, .meeting])
    XCTAssertEqual(enabledActions(paused), [.resume, .skipToday, .lunch, .meeting])
    XCTAssertTrue(working.items.contains { $0.action == .pause })
    XCTAssertTrue(paused.items.contains { $0.action == .resume })
  }

  func testConfirmYieldsTheReturnKeyToTheNewTaskRow() throws {
    let state = makeState(phase: .awaitingConfirm)
    let idle = MenuModel.timer(state: state, returnIsTaken: false, daemonAvailable: true)
    let editing = MenuModel.timer(state: state, returnIsTaken: true, daemonAvailable: true)

    XCTAssertTrue(try XCTUnwrap(idle.item(for: .confirm)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(editing.item(for: .confirm)).isEnabled)
  }

  func testEditingDoesNotDisableTheOtherVerbs() {
    let menu = MenuModel.timer(state: makeState(phase: .awaitingConfirm), returnIsTaken: true, daemonAvailable: true)

    XCTAssertEqual(enabledActions(menu), [.snooze, .skipToday, .newCycle, .lunch, .meeting])
  }

  func testCycleVerbsSitBelowTheirOwnSeparator() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.last?.map(\.action), [.skipToday, .newCycle, .lunch, .meeting])
  }

  func testTimedVerbsCarryTheirShortcutsAndCycleVerbsDoNot() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .start)?.shortcut), MenuShortcut(key: "r", modifiers: .command))
    XCTAssertEqual(try XCTUnwrap(menu.item(for: .snooze)?.shortcut), MenuShortcut(key: "s", modifiers: [.command, .shift]))
    XCTAssertEqual(try XCTUnwrap(menu.item(for: .skip)?.shortcut), MenuShortcut(key: "k", modifiers: .command))
    XCTAssertNil(try XCTUnwrap(menu.item(for: .skipToday)).shortcut)
    XCTAssertNil(try XCTUnwrap(menu.item(for: .newCycle)).shortcut)
  }

  func testItemTitlesComeFromTheAction() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .start)).title, TimerAction.start.title)
  }

  /// throwntom-46y. The Timer menu and the window's chip row are two renderings of one control, so
  /// ⌘R must not be labelled Start in the menu bar while the chip beside it names a short break.
  func testTheTimerMenuNamesThePhaseStartWouldBegin() throws {
    let owing = makeState(phase: .idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    let menu = MenuModel.timer(state: owing, returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(try XCTUnwrap(menu.items.first { $0.action == .start }).title, "Start Short break")
  }

  /// The other title the Timer menu takes from the snapshot. ⌘⇧P reads Resume only while the timer
  /// is paused, so with the service gone a retained `paused` snapshot would word it from a daemon
  /// the window has already declared missing — the same lie ⌘R is held away from, and the reason
  /// both titles have to ask `daemonAvailable` rather than only the one that was noticed first.
  func testAMenuWithNoServiceDoesNotOfferResumeFromTheDeadDaemon() throws {
    let paused = makeState(phase: .paused)

    XCTAssertEqual(
      try XCTUnwrap(MenuModel.timer(state: paused, returnIsTaken: false, daemonAvailable: true).items
        .first { $0.action == .resume }).title,
      TimerAction.resume.title,
      "with a service, a paused timer really does offer Resume",
    )
    let gone = MenuModel.timer(state: paused, returnIsTaken: false, daemonAvailable: false)
    XCTAssertNil(gone.items.first { $0.action == .resume }, "no daemon, no phase to resume")
    XCTAssertEqual(
      try XCTUnwrap(gone.items.first { $0.action == .pause }).title,
      TimerAction.pause.title,
    )
  }

  /// With the service gone the window drops its retained phase, and the menu must drop it too: a
  /// menu item naming a phase from a daemon already confirmed gone is the same lie the window
  /// stopped telling.
  func testAMenuWithNoServiceDoesNotNameAPhaseFromTheDeadDaemon() throws {
    let owing = makeState(phase: .idle, owedStage: DaemonState.Stage(state: .shortBreak, duration: 300))
    let menu = MenuModel.timer(state: owing, returnIsTaken: false, daemonAvailable: false)
    let start = try XCTUnwrap(menu.items.first { $0.action == .start })

    XCTAssertEqual(start.title, "Start")
    XCTAssertFalse(start.isEnabled)
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
    let menu = MenuModel.tasks(model: TaskWindowModel(), daemonAvailable: true)

    XCTAssertEqual(enabledActions(menu), [.newTask])
  }

  func testSelectingATaskEnablesEveryVerb() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])

    XCTAssertEqual(enabledActions(MenuModel.tasks(model: model, daemonAvailable: true)), TaskAction.allCases)
  }

  func testEditingDisablesEveryVerb() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    model.beginNewTask()

    XCTAssertTrue(MenuModel.tasks(model: model, daemonAvailable: true).items.allSatisfy { !$0.isEnabled })
  }

  func testReorderingVerbsSitBelowTheirOwnSeparator() {
    let menu = MenuModel.tasks(model: TaskWindowModel(), daemonAvailable: true)

    XCTAssertEqual(menu.groups.count, 2)
    XCTAssertEqual(menu.groups.first?.map(\.action), [.newTask, .complete, .delete, .focus])
    XCTAssertEqual(menu.groups.last?.map(\.action), [.moveUp, .moveDown])
  }

  func testEveryTaskVerbKeepsAShortcut() {
    let menu = MenuModel.tasks(model: TaskWindowModel(), daemonAvailable: true)

    XCTAssertTrue(menu.items.allSatisfy { $0.shortcut != nil })
  }

  func testFocusReadsUnfocusWhenTheSelectedTaskIsFocused() throws {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])

    model.selectedID = 1
    XCTAssertEqual(try XCTUnwrap(MenuModel.tasks(model: model, daemonAvailable: true).item(for: .focus)).title, "Focus")

    model.selectedID = 2
    XCTAssertEqual(try XCTUnwrap(MenuModel.tasks(model: model, daemonAvailable: true).item(for: .focus)).title, "Unfocus")
  }

  func testARowOverridesTheSelectionsFocusState() throws {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])
    model.selectedID = 1

    let menu = MenuModel.tasks(model: model, on: 2, daemonAvailable: true)

    XCTAssertEqual(try XCTUnwrap(menu.item(for: .focus)).title, "Unfocus")
  }

  /// The context menu names the row it was opened on, so its verbs read for that row even when
  /// the selection is elsewhere or absent.
  func testANamedRowEnablesItsOwnVerbsWhateverTheSelection() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [])
    model.selectedID = nil

    XCTAssertEqual(enabledActions(MenuModel.tasks(model: model, on: 2, daemonAvailable: true)), TaskAction.allCases)
    XCTAssertEqual(enabledActions(MenuModel.tasks(model: model, daemonAvailable: true)), [.newTask], "no row named, no selection")
  }

  func testOtherVerbsKeepTheirTitleWhateverTheFocusState() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [1])

    XCTAssertEqual(MenuModel.tasks(model: model, daemonAvailable: true).item(for: .complete)?.title, TaskAction.complete.title)
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
    let menu = MenuModel.view(showsShortcuts: false, daemonAvailable: true)
    XCTAssertEqual(menu.items.map(\.title), ["Tasks", "Stats", "Keyboard Shortcuts"])
    XCTAssertEqual(menu.item(for: .tasks)?.shortcut, MenuShortcut(key: "t", modifiers: .command))
    XCTAssertEqual(menu.item(for: .stats)?.shortcut, MenuShortcut(key: "i", modifiers: [.command, .shift]))
    XCTAssertEqual(menu.item(for: .shortcuts)?.shortcut, MenuShortcut(key: "/", modifiers: .command))
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
    XCTAssertFalse(try XCTUnwrap(MenuModel.view(showsShortcuts: true, daemonAvailable: true).item(for: .shortcuts)?.isEnabled))
  }

  func testViewActionHintsMatchShortcuts() {
    XCTAssertEqual(ViewAction.allCases.map(\.shortcutHint), ["⌘T", "⌘⇧I", "⌘/", "⌘,"])
  }

  func testOpenConfigBelongsToTheAppMenuNotTheViewMenu() {
    let menu = MenuModel.view(showsShortcuts: false, daemonAvailable: true)

    XCTAssertFalse(menu.items.contains { $0.action == .openConfig }, "the View menu keeps its three items")
    XCTAssertEqual(MenuModel.appConfig().items.map(\.title), ["Open Config File…"])
    XCTAssertEqual(MenuModel.appConfig().item(for: .openConfig)?.shortcut, MenuShortcut(key: ",", modifiers: .command))
    XCTAssertNil(ViewAction.openConfig.panel)
  }

  func testWindowCommandsAreTheViewMenuPlusTheConfigFile() {
    let menu = MenuModel.windowCommands(model: WindowModel(), daemonAvailable: true)

    XCTAssertEqual(menu.groups.count, 1, "a chip row draws no separators")
    XCTAssertEqual(menu.items.map(\.action), [.tasks, .stats, .shortcuts, .openConfig])
    XCTAssertEqual(menu.items.map(\.title), ["Tasks", "Stats", "Keyboard Shortcuts", "Open Config File…"])
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

}

// MARK: - MenuGroupsTests

@MainActor
final class MenuGroupsTests: XCTestCase {

  // MARK: Internal

  /// `body` and `groupView` both return `some View`, so there is no public API that lets a test
  /// read what shape they built. Every test below reflects the actual `TupleView`/`ForEach`
  /// storage instead of only calling the method and discarding the result -- the discipline
  /// `MenuGroups.swift`'s own doc comment on `groupView` asks for.
  func testBodyRendersEachGroupThroughGroupView() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }

    XCTAssertTrue(
      typeDescription(groups.body).contains("TupleView"),
      "the outer ForEach must build each group by calling groupView(index:group:)",
    )
  }

  func testFirstGroupHasNoLeadingDivider() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }

    XCTAssertNil(divider(in: groups.groupView(index: 0, group: menu.groups[0])), "no divider before the first group")
  }

  func testLaterGroupsGetADivider() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)
    XCTAssertGreaterThan(menu.groups.count, 1, "the divider branch needs a second group to exercise")
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }

    guard let divider = divider(in: groups.groupView(index: 1, group: menu.groups[1])) else {
      return XCTFail("expected a divider before a later group")
    }
    XCTAssertEqual(typeDescription(divider), "SwiftUI.Divider")
  }

  func testGroupViewRendersEachItemWithTheSuppliedLabel() {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)
    let groups = MenuGroups(menu: menu) { item in Text(item.title) }

    guard let content = itemContent(in: groups.groupView(index: 0, group: menu.groups[0])) else {
      return XCTFail("expected the group's items to be rendered through a ForEach")
    }
    XCTAssertTrue(typeDescription(content).contains("SwiftUI.Text"), "each item must be built with the supplied label")
  }

  // MARK: Private

  private func typeDescription(_ value: Any) -> String {
    String(reflecting: type(of: value))
  }

  /// `groupView`'s return value, unwrapped one level from the `TupleView` SwiftUI actually
  /// builds. `nil` when the mutant collapsed it to something else entirely (a bare
  /// `Optional<Divider>`, say), not just when the divider itself is absent.
  private func tupleValue(in view: Any) -> Any? {
    Mirror(reflecting: view).children.first(where: { $0.label == "value" })?.value
  }

  /// The `if index > 0 { Divider() }` half of `groupView`'s tuple, unwrapped: the value the `if`
  /// actually produced, or `nil` when it produced nothing.
  private func divider(in view: Any) -> Any? {
    guard let tuple = tupleValue(in: view) else { return nil }
    guard let wrapped = Mirror(reflecting: tuple).children.first(where: { $0.label == ".0" })?.value else { return nil }
    return Mirror(reflecting: wrapped).children.first?.value
  }

  /// The `ForEach(group) { item in label(item) }` half of `groupView`'s tuple: the closure that
  /// renders one item, whatever it was built to return.
  private func itemContent(in view: Any) -> Any? {
    guard let tuple = tupleValue(in: view) else { return nil }
    guard let forEach = Mirror(reflecting: tuple).children.first(where: { $0.label == ".1" })?.value else { return nil }
    return Mirror(reflecting: forEach).children.first(where: { $0.label == "content" })?.value
  }

}

// MARK: - ServiceMenuModelTests

/// The Timer menu's service group: one toggle whose title says what pressing it does, so the
/// menu bar carries Start and Stop exactly as the window does (ADR-006).
final class ServiceMenuModelTests: XCTestCase {
  func testRunningServiceOffersStop() {
    let menu = MenuModel.service(status: .running)

    XCTAssertEqual(menu.items.map(\.title), ["Stop Timer Service"])
    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

  func testStoppedServiceOffersStart() {
    let menu = MenuModel.service(status: .stopped)

    XCTAssertEqual(menu.items.map(\.title), ["Start Timer Service"])
  }

  func testRefusedLaunchOffersStartRatherThanARetryOfItsOwn() {
    let menu = MenuModel.service(status: .launchRefused)

    XCTAssertEqual(menu.items.map(\.title), ["Start Timer Service"])
  }

  /// Stopping the service is deliberate and heavy, so it claims no key: a stray keystroke must
  /// not be able to take the timer down.
  func testTheServiceToggleBindsNoKey() {
    XCTAssertNil(MenuModel.service(status: .running).items.first?.shortcut)
  }
}

import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - MenuCommandsTests

/// What the menu bar is actually made of, read back out of `AppMenus.body`.
///
/// SwiftUI can neither render nor describe a `Commands` tree in a test process: there is no
/// scene to install it in, and `CommandGroup` hides its content behind an opaque resolver
/// closure. So the tree is read two ways here, and between them they cover every statement in
/// the body.
///
/// The *shape* is the value's own type. `some Commands` erases nothing structural: each
/// statement a builder block contributes becomes a generic parameter, so a statement that stops
/// being built — an item, a divider, a whole menu — changes the type of `body`. The expected
/// spellings are composed from `shortcut(_:)` and `disabled(_:)` below rather than written out,
/// so an assertion reads as the menu it describes.
///
/// The *wiring* is the label closures `MenuGroups` stores, which are values and can be called
/// with a menu item and then fired, driving the same dispatch a click would.
///
/// The settings group's own buttons are not in the resolver's gift: they are read off
/// `AppMenus.appSettingsMenu`, the view the `CommandGroup` is built from, which is why they can be
/// pressed here at all.
@MainActor
final class MenuCommandsTests: XCTestCase {

  // MARK: Internal

  func testTheMenuBarCarriesTheSettingsGroupAndTheTimerViewAndTasksMenus() throws {
    let blocks = try commandBlocks(of: try makeMenus())

    XCTAssertEqual(blocks.map(head), ["CommandGroup", "CommandMenu", "CommandMenu", "CommandMenu"])
    XCTAssertEqual(blocks.dropFirst().compactMap(menuName), ["Timer", "View", "Tasks"])
  }

  /// The group that replaces the Settings item macOS installs: the config file, then the launch
  /// and notification settings under a divider.
  func testTheSettingsGroupCarriesTheConfigItemTheLoginToggleAndTheTwoSettingsItems() throws {
    XCTAssertEqual(
      shape(of: try commandBlock(0, of: try makeMenus())),
      "CommandGroup<TupleView<(MenuGroups<ViewAction, \(shortcut(button))>, "
        + "Divider, LoginItemToggle, \(button), \(button))>>",
    )
  }

  /// The config item's wiring, read off `appSettingsMenu` rather than the `CommandGroup` that
  /// carries it — a `CommandGroup` hides its content behind a resolver closure, so the group's
  /// buttons are only reachable because the items are a view of their own. The opener is the
  /// app's own, injected, so nothing is handed to a real editor here.
  func testTheConfigItemHandsOverTheFileTheDaemonReads() throws {
    var opened: URL?
    var menus = try makeMenus()
    menus.openConfigFile = { url in
      opened = url
      return true
    }

    try press(ViewAction.openConfig, in: try labels(of: try settingsGroupPart(0, of: menus)))

    XCTAssertEqual(opened, DaemonPaths.configFileToOpen())
  }

  /// The two panes below the divider. Both are System Settings windows on a real machine, so both
  /// are injected: what is asserted is that the item is wired to the one it names.
  func testTheLoginItemsSettingsItemOpensTheLoginItemsPane() throws {
    var opens = 0
    var menus = try makeMenus()
    menus.openLoginItemsSettings = { opens += 1 }
    menus.openNotificationSettings = { XCTFail("the login items item opened the notifications pane") }

    try pressButton(try settingsGroupPart(3, of: menus))

    XCTAssertEqual(opens, 1)
  }

  func testTheNotificationSettingsItemOpensTheNotificationsPane() throws {
    var opens = 0
    var menus = try makeMenus()
    menus.openNotificationSettings = { opens += 1 }
    menus.openLoginItemsSettings = { XCTFail("the notifications item opened the login items pane") }

    try pressButton(try settingsGroupPart(4, of: menus))

    XCTAssertEqual(opens, 1)
  }

  func testTheTimerMenuCarriesTheVerbsTheSnoozeSubmenuADividerAndTheServiceGroup() throws {
    let parts = try timerMenuParts(of: try makeMenus())

    XCTAssertEqual(parts.count, 4)
    XCTAssertEqual(shape(of: try part(0, of: parts)), "MenuGroups<TimerAction, \(timerVerb)>")
    XCTAssertEqual(
      shape(of: try part(1, of: parts)),
      disabled("Menu<Text, MenuGroups<SnoozeAction, \(disabled(button))>>"),
    )
    XCTAssertEqual(shape(of: try part(2, of: parts)), "Divider")
    XCTAssertEqual(shape(of: try part(3, of: parts)), "MenuGroups<ServiceAction, \(button)>")
  }

  func testTheViewMenuRendersEveryItemAsAButtonThatCarriesItsShortcut() throws {
    XCTAssertEqual(
      shape(of: try content(of: try commandBlock(2, of: try makeMenus()))),
      "MenuGroups<ViewAction, \(disabled(shortcut(button)))>",
    )
  }

  func testTheTasksMenuRendersEveryItemAsAButtonThatCarriesItsShortcut() throws {
    XCTAssertEqual(
      shape(of: try content(of: try commandBlock(3, of: try makeMenus()))),
      "MenuGroups<TaskAction, \(disabled(shortcut(button)))>",
    )
  }

  /// Lunch alone grows a length picker in the Timer menu; every other verb stays one button that
  /// sends one thing. Which of the two an item gets is the `if` in the body, and the branch it
  /// took is the only trace of that decision left in the built value.
  func testLunchAloneBecomesASubmenuAndEveryOtherVerbStaysAButton() throws {
    let verbs = try labels(of: try timerMenuPart(0, of: try makeMenus()))
    var branches = [TimerAction: String]()

    for item in verbs.labelledItems {
      let action = try XCTUnwrap((item as? MenuItem<TimerAction>)?.action)
      branches[action] = try branch(of: try XCTUnwrap(verbs.builtLabel(for: item)))
    }

    let others = branches.filter { $0.key != .lunch }
    XCTAssertEqual(branches[.lunch], "trueContent", "Lunch is the submenu")
    XCTAssertFalse(others.isEmpty, "the else branch needs a verb to exercise")
    XCTAssertTrue(others.values.allSatisfy { $0 == "falseContent" }, "every other verb is a plain button")
  }

  /// The wiring, from here down: a button built by the body is fired, and what it sent is what a
  /// click would have sent.
  func testATimerVerbButtonSendsThatVerbToTheDaemon() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)
    let verbs = try labels(of: try timerMenuPart(0, of: menus))

    try press(TimerAction.start, in: verbs)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands, [StubTransport.Request(method: "POST", path: "/v1/timer/start", body: "")])
  }

  func testALunchLengthButtonSendsThatLength() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)
    let verbs = try labels(of: try timerMenuPart(0, of: menus))
    let lunchItem = try XCTUnwrap(verbs.labelledItems.first { ($0 as? MenuItem<TimerAction>)?.action == .lunch })
    let submenu = try unwrapped(try XCTUnwrap(verbs.builtLabel(for: lunchItem)))

    try press(LunchAction.start(minutes: 30), in: try labels(of: try child("content", of: submenu)))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/timer/lunch", body: #"{"minutes":30}"#)],
    )
  }

  func testASnoozeDurationButtonPostsThatDuration() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)
    let submenu = try unwrapped(try timerMenuPart(1, of: menus))

    try press(SnoozeAction.snooze(minutes: 15), in: try labels(of: try child("content", of: submenu)))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(
      transport.commands,
      [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":15}"#)],
    )
  }

  /// The service group's own button, which drives launchd rather than the socket. The agent is a
  /// recorder: the live one would boot out the daemon of the machine running the tests.
  func testTheServiceButtonDrivesTheAgentBehindTheService() async throws {
    let agent = RecordingAgentService()
    let environment = makeEnvironment(transport: try StubTransport(states: []), agent: agent)
    let menus = AppMenus(environment: environment)
    XCTAssertEqual(menus.serviceMenu.items.map(\.title), ["Stop Timer Service"], "a dialling service offers Stop")

    try press(ServiceAction.stop, in: try labels(of: try timerMenuPart(3, of: menus)))

    try await waitUntil { environment.client.serviceStatus == .stopped }
    XCTAssertEqual(agent.calls, [.unregister])
  }

  func testAViewMenuButtonOpensThatPanel() throws {
    let menus = try makeMenus()

    try press(ViewAction.stats, in: try labels(of: try content(of: try commandBlock(2, of: menus))))

    XCTAssertEqual(menus.environment.windowModel.panel, .stats)
  }

  func testATasksMenuButtonRunsThatVerb() throws {
    let menus = try makeMenus()

    try press(TaskAction.newTask, in: try labels(of: try content(of: try commandBlock(3, of: menus))))

    XCTAssertTrue(menus.environment.model.isEditing)
  }

  // MARK: Private

  /// One Timer verb: the lunch submenu or a plain button, whichever the `if` in the body chose.
  private var timerVerb: String {
    "_ConditionalContent<"
      + disabled("Menu<Text, MenuGroups<LunchAction, \(disabled(button))>>")
      + ", \(disabled(shortcut(button)))>"
  }

  private func makeMenus() throws -> AppMenus {
    try makeMenus(try StubTransport(states: []))
  }

  private func makeMenus(_ transport: StubTransport) throws -> AppMenus {
    AppMenus(environment: AppEnvironment(transport: transport))
  }

  /// What `.keyboardShortcut(_:)` wraps a view in: three layers, one of them a trait the
  /// shortcut picker reads.
  private func shortcut(_ view: String) -> String {
    "ModifiedContent<ModifiedContent<ModifiedContent<\(view), "
      + "_EnvironmentKeyWritingModifier<Optional<KeyboardShortcut>>>, "
      + "ViewInputFlagModifier<HasKeyboardShortcut>>, "
      + "_TraitWritingModifier<KeyboardShortcutPickerOptionTraitKey>>"
  }

  /// The four blocks of the menu bar: the settings group and the three named menus.
  private func commandBlocks(of menus: AppMenus) throws -> [Any] {
    let body = menus.body
    return try tupleParts(of: body)
  }

  /// One of those four.
  private func commandBlock(_ index: Int, of menus: AppMenus) throws -> Any {
    try part(index, of: try commandBlocks(of: menus))
  }

  /// The settings group's own statements: the config item, a divider, the login toggle and the
  /// two settings items.
  private func settingsGroupPart(_ index: Int, of menus: AppMenus) throws -> Any {
    try part(index, of: try tupleParts(of: menus.appSettingsMenu))
  }

  /// The Timer menu's own statements: the verbs, the snooze submenu, the divider and the
  /// service group.
  private func timerMenuParts(of menus: AppMenus) throws -> [Any] {
    try tupleParts(of: try content(of: try commandBlock(1, of: menus)))
  }

  /// One of those four.
  private func timerMenuPart(_ index: Int, of menus: AppMenus) throws -> Any {
    try part(index, of: try timerMenuParts(of: menus))
  }

  /// A `MenuGroups` at some position in the tree, ready to be asked what it builds for an item.
  private func labels(of value: Any) throws -> MenuGroupsLabels {
    try XCTUnwrap(value as? MenuGroupsLabels, "\(shape(of: value)) is not a MenuGroups")
  }

  /// Runs a button's stored action, the way choosing it would.
  private func pressButton(_ view: Any) throws {
    let button = try unwrapped(view)
    let action = try XCTUnwrap(
      try child("closure", of: try child("action", of: button)) as? @MainActor () -> Void,
      "\(shape(of: button)) has no button action to press",
    )
    action()
  }

  /// The name a `CommandMenu` shows in the menu bar.
  private func menuName(of command: Any) -> String? {
    guard
      let name = try? child("name", of: command),
      let storage = try? child("storage", of: name),
      let localized = Mirror(reflecting: storage).children.first?.value,
      let key = try? child("key", of: localized),
      let text = try? child("key", of: key)
    else {
      return nil
    }
    return text as? String
  }

}

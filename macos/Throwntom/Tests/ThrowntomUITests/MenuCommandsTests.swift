import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - MenuGroupsLabels

/// `MenuGroups` keeps the closure that turns one menu item into its button, but the type that
/// closure returns cannot be named outside the body that built it — it is a stack of SwiftUI's
/// own modifier types. A protocol declared here and adopted by `MenuGroups` reaches it anyway:
/// the conformance is generic over `Action`, so matching an item to its menu stays the
/// compiler's job rather than a cast of ours.
protocol MenuGroupsLabels {
  var labelledItems: [Any] { get }

  func builtLabel(for item: Any) -> Any?
}

// MARK: - MenuGroups + MenuGroupsLabels

extension MenuGroups: MenuGroupsLabels {
  var labelledItems: [Any] {
    menu.items
  }

  func builtLabel(for item: Any) -> Any? {
    guard let item = item as? MenuItem<Action> else { return nil }
    return label(item)
  }
}

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

    try fire(verbs, action: TimerAction.start)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands, [StubTransport.Request(method: "POST", path: "/v1/timer/start", body: "")])
  }

  func testALunchLengthButtonSendsThatLength() async throws {
    let transport = try StubTransport(states: [])
    let menus = try makeMenus(transport)
    let verbs = try labels(of: try timerMenuPart(0, of: menus))
    let lunchItem = try XCTUnwrap(verbs.labelledItems.first { ($0 as? MenuItem<TimerAction>)?.action == .lunch })
    let submenu = try unwrapped(try XCTUnwrap(verbs.builtLabel(for: lunchItem)))

    try fire(try labels(of: try child("content", of: submenu)), action: LunchAction.start(minutes: 30))

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

    try fire(try labels(of: try child("content", of: submenu)), action: SnoozeAction.snooze(minutes: 15))

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

    try fire(try labels(of: try timerMenuPart(3, of: menus)), action: ServiceAction.stop)

    try await waitUntil { environment.client.serviceStatus == .stopped }
    XCTAssertEqual(agent.calls, [.unregister])
  }

  func testAViewMenuButtonOpensThatPanel() throws {
    let menus = try makeMenus()

    try fire(try labels(of: try content(of: try commandBlock(2, of: menus))), action: ViewAction.stats)

    XCTAssertEqual(menus.environment.windowModel.panel, .stats)
  }

  func testATasksMenuButtonRunsThatVerb() throws {
    let menus = try makeMenus()

    try fire(try labels(of: try content(of: try commandBlock(3, of: menus))), action: TaskAction.newTask)

    XCTAssertTrue(menus.environment.model.isEditing)
  }

  // MARK: Private

  /// How SwiftUI spells a plain menu button in a type.
  private let button = "Button<Text>"

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

  /// What `.disabled(_:)` wraps a view in.
  private func disabled(_ view: String) -> String {
    "ModifiedContent<\(view), _EnvironmentKeyTransformModifier<Bool>>"
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

  /// The Timer menu's own statements: the verbs, the snooze submenu, the divider and the
  /// service group.
  private func timerMenuParts(of menus: AppMenus) throws -> [Any] {
    try tupleParts(of: try content(of: try commandBlock(1, of: menus)))
  }

  /// One of those four.
  private func timerMenuPart(_ index: Int, of menus: AppMenus) throws -> Any {
    try part(index, of: try timerMenuParts(of: menus))
  }

  /// A statement's position in a builder block, read as a failure rather than a trap when the
  /// statement is gone: an out-of-range read kills the whole test process, and a mutation run
  /// reads a dead process as a crash rather than as the mutant having been caught.
  private func part(_ index: Int, of parts: [Any]) throws -> Any {
    try XCTUnwrap(
      parts.indices.contains(index) ? parts[index] : nil,
      "nothing at position \(index): the body built \(parts.count) of them",
    )
  }

  private func tupleParts(of value: Any) throws -> [Any] {
    Mirror(reflecting: try child("value", of: value)).children.map(\.value)
  }

  private func child(_ label: String, of value: Any) throws -> Any {
    let children = Mirror(reflecting: value).children
    return try XCTUnwrap(
      children.first { $0.label == label }?.value,
      "no \(label) in \(shape(of: value)), which has \(children.compactMap(\.label))",
    )
  }

  private func content(of value: Any) throws -> Any {
    try child("content", of: value)
  }

  /// A `MenuGroups` at some position in the tree, ready to be asked what it builds for an item.
  private func labels(of value: Any) throws -> MenuGroupsLabels {
    try XCTUnwrap(value as? MenuGroupsLabels, "\(shape(of: value)) is not a MenuGroups")
  }

  /// Builds the button for one action and runs it, the way choosing that item would.
  private func fire<Action: MenuAction>(_ groups: MenuGroupsLabels, action: Action) throws {
    let item = try XCTUnwrap(
      groups.labelledItems.first { ($0 as? MenuItem<Action>)?.action == action },
      "no \(action) in this menu",
    )
    let view = try unwrapped(try XCTUnwrap(groups.builtLabel(for: item)))
    let press = try XCTUnwrap(
      try child("closure", of: try child("action", of: view)) as? @MainActor () -> Void,
      "\(shape(of: view)) has no button action to press",
    )
    press()
  }

  /// Which half of an `if`/`else` the builder filled in.
  private func branch(of view: Any) throws -> String {
    try XCTUnwrap(Mirror(reflecting: try child("storage", of: view)).children.first?.label)
  }

  /// What that half was filled in with.
  private func branchContent(of view: Any) throws -> Any {
    try XCTUnwrap(Mirror(reflecting: try child("storage", of: view)).children.first?.value)
  }

  /// A view with what the body wrapped it in taken back off: the `.keyboardShortcut` and
  /// `.disabled` layers, and the `if`/`else` storage that holds only the branch that was built.
  private func unwrapped(_ view: Any) throws -> Any {
    var result = view
    while true {
      switch head(result) {
      case "ModifiedContent": result = try content(of: result)
      case "_ConditionalContent": result = try branchContent(of: result)
      default: return result
      }
    }
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

  /// A value's type, as SwiftUI spells it, with the module names taken out so an expected shape
  /// reads as the menu it describes.
  private func shape(of value: Any) -> String {
    var text = String(reflecting: type(of: value))
    for module in ["SwiftUI.", "ThrowntomUI.", "ThrowntomClient.", "Swift."] {
      text = text.replacingOccurrences(of: module, with: "")
    }
    return text
  }

  private func head(_ value: Any) -> String {
    String(shape(of: value).prefix { $0 != "<" })
  }

}

import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class TaskContextMenuTests: XCTestCase {

  // MARK: Internal

  func testHintLineIsBuiltFromTaskActionHints() {
    XCTAssertEqual(TaskHints.line(focused: false), "⌘N new · ⌘⏎ done · ⌘⇧F focus · ⌥↑↓ move · ⌘⌫ delete")
  }

  /// Focus is a toggle, and until this the only thing that said so was the context menu — which a
  /// reader has to already suspect exists before they can find it (throwntom-bxd.16).
  func testHintLineNamesTheUndoOnAFocusedRow() {
    XCTAssertEqual(TaskHints.line(focused: true), "⌘N new · ⌘⏎ done · ⌘⇧F unfocus · ⌥↑↓ move · ⌘⌫ delete")
  }

  func testChoosingAnItemActsOnThatRowNotTheSelection() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    environment.model.sync(tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []), focusedTaskIDs: [])
    environment.model.selectedID = 7
    let menu = TaskContextMenu(task: makeTask(id: 8), environment: environment)
    menu.run(.complete)
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.first?.body, #"{"line":"task done 2"}"#)
    XCTAssertEqual(environment.model.selectedID, 8)
  }

  func testTheMenuReadsForTheClickedRowNotTheSelection() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    environment.model.sync(tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []), focusedTaskIDs: [8])
    environment.model.selectedID = nil

    let menu = TaskContextMenu(task: makeTask(id: 8), environment: environment).menu

    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled), "the clicked row is a valid target for every verb")
    XCTAssertEqual(try XCTUnwrap(menu.item(for: .focus)).title, "Unfocus", "and it is the clicked row's focus state")
  }

  func testNewTaskFromTheMenuOpensTheEditor() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let menu = TaskContextMenu(task: makeTask(id: 1), environment: environment)
    menu.run(.newTask)
    XCTAssertTrue(environment.model.isEditing)
    _ = menu.body
  }

  /// What the body is actually built from: every item as a disabled-aware button. Named by
  /// SwiftUI's own types, the way `MenuCommandsTests` pins `AppMenus`.
  func testBodyIsMenuGroupsOfDisabledAwareButtons() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let menu = TaskContextMenu(task: makeTask(id: 1), environment: environment)

    XCTAssertEqual(shape(of: menu.body), "MenuGroups<TaskAction, \(disabled(button))>")
  }

  /// The wiring behind that shape: pressing the button a menu item built runs `run(item.action)`,
  /// the same dispatch a click would drive — not merely `menu.run(_:)` called directly.
  func testPressingAnItemsButtonRunsItsAction() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    environment.model.sync(tasks: TaskList(active: [makeTask(id: 7), makeTask(id: 8)], completed: []), focusedTaskIDs: [])
    environment.model.selectedID = 7
    let menu = TaskContextMenu(task: makeTask(id: 8), environment: environment)

    try press(.complete, in: try labels(of: menu.body))

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.first?.body, #"{"line":"task done 2"}"#)
    XCTAssertEqual(environment.model.selectedID, 8, "the button acted on the clicked row, not the selection")
  }

  // MARK: Private

  /// How SwiftUI spells a plain menu button in a type.
  private let button = "Button<Text>"

  /// What `.disabled(_:)` wraps a view in.
  private func disabled(_ view: String) -> String {
    "ModifiedContent<\(view), _EnvironmentKeyTransformModifier<Bool>>"
  }

  /// A `MenuGroups` built by the body, ready to be asked what it built for an item — the same
  /// `MenuGroupsLabels` technique `MenuCommandsTests` uses to reach `AppMenus`' menus.
  private func labels(of value: Any) throws -> MenuGroupsLabels {
    try XCTUnwrap(value as? MenuGroupsLabels, "\(shape(of: value)) is not a MenuGroups")
  }

  /// Builds the button for one action and presses it, the way choosing that item would.
  private func press(_ action: TaskAction, in groups: MenuGroupsLabels) throws {
    let item = try XCTUnwrap(
      groups.labelledItems.first { ($0 as? MenuItem<TaskAction>)?.action == action },
      "no \(action) in this menu",
    )
    let view = try unwrapped(try XCTUnwrap(groups.builtLabel(for: item)))
    let press = try XCTUnwrap(
      try child("closure", of: try child("action", of: view)) as? @MainActor () -> Void,
      "\(shape(of: view)) has no button action to press",
    )
    press()
  }

}

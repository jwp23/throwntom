import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// The key equivalents the app claims, checked as a whole. Two menu items on one key equivalent is
/// a bug macOS resolves arbitrarily and silently, so it has to be caught here rather than in use.
@MainActor
final class MenuBindingTests: XCTestCase {

  // MARK: Internal

  func testNoTwoCommandsShareAKeyEquivalent() {
    for phase in Self.phases {
      for isEditing in [false, true] {
        var owner = Self.reserved
        for binding in bindings(phase: phase, isEditing: isEditing) {
          if let taken = owner[binding.shortcut] {
            let where_ = "phase \(String(describing: phase)), editing \(isEditing)"
            XCTFail("\(binding.shortcut.hint) is bound to both \(taken) and \(binding.title) (\(where_))")
          }
          owner[binding.shortcut] = binding.title
        }
      }
    }
  }

  /// The binding is what macOS listens for; `shortcutHint` is what the chips, hint lines and cheat
  /// sheet print. Nothing in the type system ties them together, so rebinding a key without
  /// editing its hint would leave the UI advertising a keystroke that does nothing.
  func testEveryDisplayedHintMatchesTheKeyItIsBoundTo() {
    for phase in Self.phases {
      for binding in bindings(phase: phase, isEditing: false) {
        XCTAssertEqual(binding.displayedHint, binding.shortcut.hint, binding.title)
      }
    }
  }

  func testHintSpellsOutModifiersAndNamedKeys() {
    XCTAssertEqual(MenuShortcut(key: "r", modifiers: .command).hint, "⌘R")
    XCTAssertEqual(MenuShortcut(key: "s", modifiers: [.command, .shift]).hint, "⌘⇧S")
    XCTAssertEqual(MenuShortcut(key: .return, modifiers: []).hint, "⏎")
    XCTAssertEqual(MenuShortcut(key: .delete, modifiers: .command).hint, "⌘⌫")
    XCTAssertEqual(MenuShortcut(key: .upArrow, modifiers: .option).hint, "⌥↑")
    XCTAssertEqual(MenuShortcut(key: ",", modifiers: .command).hint, "⌘,")
  }

  // MARK: Private

  private struct Binding {
    let title: String
    let displayedHint: String
    let shortcut: MenuShortcut
  }

  private static let phases: [DaemonState.Phase?] =
    [nil, .idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused]

  /// AppKit binds Quit itself, so no menu model of ours may claim it.
  private static let reserved = [MenuShortcut(key: "q", modifiers: .command): "Quit Throwntom"]

  /// Every key equivalent the app binds for one snapshot: the four menu models, with the task menu
  /// given a selected task so none of its verbs is withheld.
  private func bindings(phase: DaemonState.Phase?, isEditing: Bool) -> [Binding] {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    let state = phase.map { makeState(phase: $0, morningPending: true) }
    return collect(MenuModel.timer(state: state, isEditing: isEditing)) { $0.shortcutHint }
      + collect(MenuModel.tasks(model: model)) { $0.shortcutHint }
      + collect(MenuModel.view(model: WindowModel())) { $0.shortcutHint }
      + collect(MenuModel.appConfig()) { $0.shortcutHint }
  }

  private func collect<Action>(_ menu: MenuModel<Action>, hint: (Action) -> String) -> [Binding] {
    menu.items.compactMap { item in
      item.shortcut.map { Binding(title: item.title, displayedHint: hint(item.action), shortcut: $0) }
    }
  }

}

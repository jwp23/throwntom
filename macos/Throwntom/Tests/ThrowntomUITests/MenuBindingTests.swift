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
        let commands = commands(phase: phase, isEditing: isEditing)
        assertEveryMenuContributed(commands, phase: phase)
        var owner = Self.reserved
        for command in commands.compactMap(Bound.init) {
          if let taken = owner[command.shortcut] {
            let context = "phase \(String(describing: phase)), editing \(isEditing)"
            XCTFail("\(command.shortcut.hint) is bound to both \(taken) and \(command.title) (\(context))")
          }
          owner[command.shortcut] = command.title
        }
      }
    }
  }

  /// The binding is what macOS listens for; `shortcutHint` is what the chips, hint lines and cheat
  /// sheet print. Nothing in the type system ties them together, so rebinding a key without editing
  /// its hint would leave the UI advertising a keystroke that does nothing — and a verb that binds
  /// no key at all must advertise none, or the cheat sheet invents one.
  func testEveryDisplayedHintMatchesTheKeyItIsBoundTo() {
    for phase in Self.phases {
      // Both editing states, for the same reason as the collision test: editing changes which
      // verbs are enabled, and this asserts that it never changes what any of them advertises.
      for isEditing in [false, true] {
        let commands = commands(phase: phase, isEditing: isEditing)
        assertEveryMenuContributed(commands, phase: phase)
        for command in commands {
          XCTAssertEqual(command.displayedHint, command.shortcut?.hint ?? "", command.title)
        }
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

  /// One menu item flattened to what this file checks: what it is called, what it advertises, and
  /// what it binds. `shortcut` is nil for the verbs that deliberately have no key.
  private struct Command {
    let title: String
    let displayedHint: String
    let shortcut: MenuShortcut?
  }

  /// A `Command` that does bind a key.
  private struct Bound {
    init?(_ command: Command) {
      guard let shortcut = command.shortcut else { return nil }
      title = command.title
      self.shortcut = shortcut
    }

    let title: String
    let shortcut: MenuShortcut
  }

  private static let phases: [DaemonState.Phase?] =
    [nil, .idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused]

  /// AppKit binds Quit itself, so no menu model of ours may claim it.
  private static let reserved = [MenuShortcut(key: "q", modifiers: .command): "Quit Throwntom"]

  /// Timer 6 + service 1 + Tasks 6 + View 3 + config 1. Asserting the exact number keeps these
  /// tests from passing vacuously: an empty list would satisfy every loop below while checking
  /// nothing.
  private static let commandCount = 17

  /// Every command the app offers for one snapshot: the four menu models, with the task menu given
  /// a selected task so none of its verbs is withheld.
  private func commands(phase: DaemonState.Phase?, isEditing: Bool) -> [Command] {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    let state = phase.map { makeState(phase: $0, morningPending: true) }
    return collect(MenuModel.timer(state: state, isEditing: isEditing)) { $0.shortcutHint }
      + collect(MenuModel.service(connection: .connected, registrationFailed: false)) { $0.shortcutHint }
      + collect(MenuModel.tasks(model: model)) { $0.shortcutHint }
      + collect(MenuModel.view(model: WindowModel())) { $0.shortcutHint }
      + collect(MenuModel.appConfig()) { $0.shortcutHint }
  }

  private func collect<Action>(_ menu: MenuModel<Action>, hint: (Action) -> String) -> [Command] {
    menu.items.map { Command(title: $0.title, displayedHint: hint($0.action), shortcut: $0.shortcut) }
  }

  private func assertEveryMenuContributed(_ commands: [Command], phase: DaemonState.Phase?) {
    XCTAssertEqual(
      commands.count,
      Self.commandCount,
      "every menu model should contribute in \(String(describing: phase)); update commandCount when adding a command",
    )
  }

}

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
      for returnIsTaken in [false, true] {
        let commands = commands(phase: phase, returnIsTaken: returnIsTaken)
        assertEveryMenuContributed(commands, phase: phase)
        var owner = Self.reserved
        for command in commands.compactMap(Bound.init) {
          if let taken = owner[command.shortcut] {
            let context = "phase \(String(describing: phase)), Return taken \(returnIsTaken)"
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
      // Both answers to `returnIsTaken`, for the same reason as the collision test: it changes
      // which verbs are enabled, and this asserts it never changes what any of them advertises.
      for returnIsTaken in [false, true] {
        let commands = commands(phase: phase, returnIsTaken: returnIsTaken)
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
    XCTAssertEqual(MenuShortcut(key: .return, modifiers: .shift).hint, "⇧⏎")
    XCTAssertEqual(MenuShortcut(key: .escape, modifiers: []).hint, "⎋")
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

  /// The key equivalents no menu model of ours may claim, because something outside them already
  /// answers the keystroke.
  ///
  /// Two kinds, and the second is why this list is worth having. AppKit and SwiftUI install the
  /// first without being asked — Quit, Hide, Close, Minimize, Full Screen and the whole Edit menu
  /// arrive in every app, and a second claim on one of them is resolved arbitrarily. The rest are
  /// conventions the platform has trained the user with rather than items we are handed: Find,
  /// which any window holding a list is expected to answer, and Print. Those two are how ⌘F and ⌘P
  /// reached a user — this file compared our bindings only against each other, so a collision with
  /// the platform was invisible to it by construction and no test could have caught either.
  ///
  /// Escape is ours rather than the system's, and is here for the same reason: `MainWindow` and the
  /// cheat sheet both answer it (`WindowModel.dismiss`), so a menu item that bound it would take
  /// the key away from the dismissal it is the only route to.
  ///
  /// ⌘, is deliberately absent. `CommandGroup(replacing: .appSettings)` takes AppKit's Settings
  /// item out and puts ours in its place, so the key is ours and there is nothing left to collide
  /// with — which is the shape of an intended match rather than a collision.
  private static let reserved: [MenuShortcut: String] = [
    MenuShortcut(key: "q", modifiers: .command): "Quit Throwntom",
    MenuShortcut(key: "h", modifiers: .command): "Hide Throwntom",
    MenuShortcut(key: "h", modifiers: [.command, .option]): "Hide Others",
    MenuShortcut(key: "w", modifiers: .command): "Close Window",
    MenuShortcut(key: "m", modifiers: .command): "Minimize",
    MenuShortcut(key: "f", modifiers: [.command, .control]): "Enter Full Screen",
    MenuShortcut(key: "z", modifiers: .command): "Undo",
    MenuShortcut(key: "z", modifiers: [.command, .shift]): "Redo",
    MenuShortcut(key: "x", modifiers: .command): "Cut",
    MenuShortcut(key: "c", modifiers: .command): "Copy",
    MenuShortcut(key: "v", modifiers: .command): "Paste",
    MenuShortcut(key: "a", modifiers: .command): "Select All",
    MenuShortcut(key: "f", modifiers: .command): "Find",
    MenuShortcut(key: "p", modifiers: .command): "Print",
    MenuShortcut(key: .escape, modifiers: []): "Dismiss",
  ]

  /// Timer 7 + snooze 6 + service 1 + Tasks 6 + View 3 + config 1. Asserting the exact number
  /// keeps these tests from passing vacuously: an empty list would satisfy every loop below while
  /// checking nothing.
  private static let commandCount = 24

  /// Every command the app offers for one snapshot: the four menu models, with the task menu given
  /// a selected task so none of its verbs is withheld.
  private func commands(phase: DaemonState.Phase?, returnIsTaken: Bool) -> [Command] {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    let state = phase.map { makeState(phase: $0, morningPending: true) }
    return collect(MenuModel.timer(state: state, returnIsTaken: returnIsTaken, daemonAvailable: true)) { $0.shortcutHint }
      // The snooze submenu binds no keys, and that is the claim worth holding it to: its
      // durations are pointer-driven so they cannot collide with anything, and ⌘⇧S stays on
      // the Timer menu's own Snooze.
      + collect(MenuModel.snooze(state: state, daemonAvailable: true)) { _ in "" }
      + collect(MenuModel.service(status: .running)) { $0.shortcutHint }
      + collect(MenuModel.tasks(model: model, daemonAvailable: true)) { $0.shortcutHint }
      + collect(MenuModel.view(showsShortcuts: false, daemonAvailable: true)) { $0.shortcutHint }
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

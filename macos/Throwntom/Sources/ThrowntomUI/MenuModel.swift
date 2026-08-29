import SwiftUI
import ThrowntomClient

// MARK: - MenuAction

/// A verb that can appear in a command menu.
protocol MenuAction: Hashable {
  var title: String { get }
}

// MARK: - TimerAction + MenuAction

extension TimerAction: MenuAction { }

// MARK: - TaskAction + MenuAction

extension TaskAction: MenuAction { }

// MARK: - ViewAction + MenuAction

extension ViewAction: MenuAction { }

// MARK: - MenuShortcut

/// The key binding of a menu item. Separate from the item so items without one are expressible.
struct MenuShortcut: Equatable {
  let key: KeyEquivalent
  let modifiers: EventModifiers

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
  }

  static func ==(lhs: MenuShortcut, rhs: MenuShortcut) -> Bool {
    lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
  }
}

// MARK: - MenuItem

/// One row of a command menu: the verb it runs, how to reach it and whether it can run now.
struct MenuItem<Action: MenuAction>: Identifiable {
  let action: Action
  let shortcut: MenuShortcut?
  let isEnabled: Bool

  var title: String {
    action.title
  }

  var id: Action {
    action
  }
}

// MARK: - MenuModel

/// A command menu as plain data: groups of items, drawn with a separator between groups.
/// Deciding what a menu offers here keeps that decision out of the SwiftUI `Commands` body.
struct MenuModel<Action: MenuAction> {
  let groups: [[MenuItem<Action>]]
}

extension MenuModel where Action == TimerAction {
  /// The Timer menu for a daemon snapshot. A verb is enabled when the daemon would accept it,
  /// except that Confirm gives up the Return key while the inline new-task row is open.
  static func timer(state: DaemonState?, isEditing: Bool) -> MenuModel {
    let available = state.map(TimerActions.available(for:)) ?? []
    func item(_ action: TimerAction, _ shortcut: MenuShortcut?, isEnabled: Bool? = nil) -> MenuItem<TimerAction> {
      MenuItem(action: action, shortcut: shortcut, isEnabled: isEnabled ?? available.contains(action))
    }
    return MenuModel(groups: [
      [
        item(.start, MenuShortcut(key: "r", modifiers: .command)),
        item(
          .confirm,
          MenuShortcut(key: .return, modifiers: []),
          isEnabled: available.contains(.confirm) && !isEditing,
        ),
        item(TimerActions.pauseOrResume(for: state?.state), MenuShortcut(key: "p", modifiers: .command)),
        item(.snooze, MenuShortcut(key: "s", modifiers: [.command, .shift])),
      ],
      [
        item(.skipToday, nil),
        item(.newCycle, nil),
      ],
    ])
  }
}

extension MenuModel where Action == TaskAction {
  /// The Tasks menu for the current editor state. Every verb but New Task needs a selection,
  /// and the inline new-task row owns the keyboard while it is open.
  @MainActor
  static func tasks(model: TaskWindowModel) -> MenuModel {
    func item(_ action: TaskAction, _ key: KeyEquivalent, _ modifiers: EventModifiers) -> MenuItem<TaskAction> {
      MenuItem(
        action: action,
        shortcut: MenuShortcut(key: key, modifiers: modifiers),
        isEnabled: model.canPerform(action),
      )
    }
    return MenuModel(groups: [
      [
        item(.newTask, "n", .command),
        item(.complete, .return, .command),
        item(.delete, .delete, .command),
        item(.focus, "f", .command),
      ],
      [
        item(.moveUp, .upArrow, .option),
        item(.moveDown, .downArrow, .option),
      ],
    ])
  }
}

extension MenuModel where Action == ViewAction {
  @MainActor
  static func view(model: WindowModel) -> MenuModel {
    MenuModel(groups: [[
      MenuItem(action: .tasks, shortcut: MenuShortcut(key: "t", modifiers: .command), isEnabled: true),
      MenuItem(action: .stats, shortcut: MenuShortcut(key: "d", modifiers: [.command, .shift]), isEnabled: true),
      MenuItem(
        action: .shortcuts,
        shortcut: MenuShortcut(key: "/", modifiers: .command),
        isEnabled: !model.showsShortcuts,
      ),
    ]])
  }
}

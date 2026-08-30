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

// MARK: - ServiceAction + MenuAction

extension ServiceAction: MenuAction { }

// MARK: - SnoozeAction + MenuAction

extension SnoozeAction: MenuAction { }

// MARK: - MenuShortcut

/// The key binding of a menu item. Separate from the item so items without one are expressible.
struct MenuShortcut: Hashable {

  // MARK: Internal

  let key: KeyEquivalent
  let modifiers: EventModifiers

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
  }

  /// The canonical way to write this binding: the modifier glyphs in the order this app writes them
  /// (⌘ before ⇧), then the key. Each action still carries its own `shortcutHint` for display, since
  /// those live in `ThrowntomClient` and cannot reach this type; `MenuBindingTests` holds every one
  /// of them to this rendering, so a rebinding cannot leave the UI advertising the old key.
  var hint: String {
    var glyphs = ""
    if modifiers.contains(.command) {
      glyphs += "⌘"
    }
    if modifiers.contains(.shift) {
      glyphs += "⇧"
    }
    if modifiers.contains(.option) {
      glyphs += "⌥"
    }
    if modifiers.contains(.control) {
      glyphs += "⌃"
    }
    return glyphs + Self.glyph(for: key)
  }

  static func ==(lhs: MenuShortcut, rhs: MenuShortcut) -> Bool {
    lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key.character)
    hasher.combine(modifiers.rawValue)
  }

  // MARK: Private

  /// The keys that print as a symbol rather than as themselves.
  private static func glyph(for key: KeyEquivalent) -> String {
    switch key.character {
    case KeyEquivalent.return.character: "⏎"
    case KeyEquivalent.delete.character: "⌫"
    case KeyEquivalent.upArrow.character: "↑"
    case KeyEquivalent.downArrow.character: "↓"
    default: String(key.character).uppercased()
    }
  }

}

// MARK: - MenuItem

/// One row of a command menu: the verb it runs, how to reach it and whether it can run now.
struct MenuItem<Action: MenuAction>: Identifiable {
  init(action: Action, shortcut: MenuShortcut?, isEnabled: Bool, title: String? = nil) {
    self.action = action
    self.shortcut = shortcut
    self.isEnabled = isEnabled
    self.title = title ?? action.title
  }

  let action: Action
  let shortcut: MenuShortcut?
  let isEnabled: Bool
  /// Usually the action's own title; a toggle verb passes the wording for the current state.
  let title: String

  var id: Action {
    action
  }
}

// MARK: - MenuModel

/// A command menu as plain data: groups of items, drawn with a separator between groups.
/// Deciding what a menu offers here keeps that decision out of the SwiftUI `Commands` body.
struct MenuModel<Action: MenuAction> {
  let groups: [[MenuItem<Action>]]

  /// Every item in menu order, ignoring where the separators fall.
  var items: [MenuItem<Action>] {
    groups.flatMap { $0 }
  }
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
        item(.skip, MenuShortcut(key: "k", modifiers: .command)),
        item(.snooze, MenuShortcut(key: "s", modifiers: [.command, .shift])),
      ],
      [
        item(.skipToday, nil),
        item(.newCycle, nil),
      ],
    ])
  }
}

extension MenuModel where Action == SnoozeAction {
  /// The snooze lifecycle as one menu: how long to defer the reminder, a way to say a duration
  /// the presets do not cover, and the undo. It is the whole feature in one place because the
  /// user's question — "not now, but when?" — is one question.
  ///
  /// The durations stay enabled while a snooze is already running: the daemon replaces the
  /// deadline rather than refusing (`outstandingReminder.suppress`), so changing your mind about
  /// how long is one click, not a cancel that rings the reminder you were deferring.
  static func snooze(state: DaemonState?) -> MenuModel {
    snooze(
      canDefer: state.map { TimerActions.available(for: $0).contains(.snooze) } ?? false,
      isSnoozed: state?.snoozeUntil != nil,
    )
  }

  /// The same menu from what a caller has already decided. The window works this way because its
  /// chip row is blanked when the daemon is gone: reading the raw state again there would offer
  /// an enabled Cancel Snooze for a daemon the rest of the window has already given up on.
  static func snooze(canDefer: Bool, isSnoozed: Bool) -> MenuModel {
    func item(_ action: SnoozeAction, isEnabled: Bool) -> MenuItem<SnoozeAction> {
      MenuItem(action: action, shortcut: nil, isEnabled: isEnabled)
    }
    return MenuModel(groups: [
      SnoozeActions.presets.map { item(.snooze(minutes: $0), isEnabled: canDefer) }
        + [item(.custom, isEnabled: canDefer)],
      [item(.cancel, isEnabled: isSnoozed)],
    ])
  }
}

extension MenuModel where Action == ServiceAction {
  /// The timer service's own group in the Timer menu: one toggle, worded for what pressing it
  /// does. Always enabled — the whole point is that it works when nothing else does.
  static func service(connection: DaemonClient.Connection, registrationFailed: Bool) -> MenuModel {
    let action = ServiceActions.startOrStop(connection: connection, registrationFailed: registrationFailed)
    return MenuModel(groups: [[MenuItem(action: action, shortcut: nil, isEnabled: true)]])
  }
}

extension MenuModel where Action == TaskAction {
  /// The Tasks menu for the current editor state. Every verb but New Task needs a selection,
  /// and the inline new-task row owns the keyboard while it is open. `taskID` names the row the
  /// menu was opened on, which need not be the selected one; passing none reads for the selection.
  /// Every verb — whether it can run, and whether Focus reads as its own undo — answers for that
  /// row, so a context menu on an unselected row does not describe a different task.
  @MainActor
  static func tasks(model: TaskWindowModel, on taskID: Int? = nil) -> MenuModel {
    // Resolved once: whether a verb can run and whether Focus reads as its own undo are two
    // questions about one row, and reading the row twice is how they came to disagree.
    let row = taskID ?? model.selectedID
    let focused = model.isFocused(row)
    func item(_ action: TaskAction, _ key: KeyEquivalent, _ modifiers: EventModifiers) -> MenuItem<TaskAction> {
      MenuItem(
        action: action,
        shortcut: MenuShortcut(key: key, modifiers: modifiers),
        isEnabled: model.canPerform(action, on: row),
        title: action.title(focused: focused),
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
  /// The View menu: the two panels and the cheat sheet.
  @MainActor
  static func view(model: WindowModel) -> MenuModel {
    MenuModel(groups: [[
      MenuItem(action: .tasks, shortcut: MenuShortcut(key: "t", modifiers: .command), isEnabled: true),
      MenuItem(action: .stats, shortcut: MenuShortcut(key: "i", modifiers: [.command, .shift]), isEnabled: true),
      MenuItem(
        action: .shortcuts,
        shortcut: MenuShortcut(key: "/", modifiers: .command),
        isEnabled: !model.showsShortcuts,
      ),
    ]])
  }

  /// The app menu's config item, where macOS expects ⌘, to sit.
  static func appConfig() -> MenuModel {
    MenuModel(groups: [[
      MenuItem(action: .openConfig, shortcut: MenuShortcut(key: ",", modifiers: .command), isEnabled: true)
    ]])
  }

  /// The chip row under the timer verbs: every command the menu bar shows something for, in one
  /// group, so a new user reaches the panels, the cheat sheet and the config without the menu bar.
  @MainActor
  static func windowCommands(model: WindowModel) -> MenuModel {
    MenuModel(groups: [view(model: model).items + appConfig().items])
  }
}

import SwiftUI
import ThrowntomClient

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
  /// The Timer menu for a daemon snapshot. A verb is enabled when it is one this state offers
  /// (`TimerActions.available(for:)`), except that Confirm gives up its key while something in
  /// front of it is using it — a text field the user is typing in, or a sheet whose default button
  /// is Return. Which surfaces those are is the caller's to know (`AppEnvironment.returnIsTaken`);
  /// `returnIsTaken` is the answer, not the question. Start is worded for the phase it would begin,
  /// the way the play/pause item is worded for what pressing it does.
  ///
  /// `daemonAvailable` is asked separately from the snapshot because the client goes on holding
  /// that snapshot after the service is gone — the cheat sheet and the focus list read it, and
  /// blanking it to dress the menus would blank those too. Reading enablement from the retained
  /// state alone is what left ⌘⇧P and ⌘K firing into a dead daemon with no control on screen to
  /// look wrong.
  static func timer(state: DaemonState?, returnIsTaken: Bool, daemonAvailable: Bool) -> MenuModel {
    let available = daemonAvailable ? state.map(TimerActions.available(for:)) ?? [] : []
    func item(
      _ action: TimerAction,
      _ shortcut: MenuShortcut?,
      isEnabled: Bool? = nil,
      title: String? = nil,
    ) -> MenuItem<TimerAction> {
      MenuItem(
        action: action,
        shortcut: shortcut,
        isEnabled: isEnabled ?? available.contains(action),
        title: title,
      )
    }
    return MenuModel(groups: [
      [
        item(
          .start,
          MenuShortcut(key: "r", modifiers: .command),
          title: TimerActions.startTitle(for: daemonAvailable ? state : nil),
        ),
        item(
          .confirm,
          MenuShortcut(key: .return, modifiers: .shift),
          isEnabled: available.contains(.confirm) && !returnIsTaken,
        ),
        item(
          TimerActions.pauseOrResume(for: daemonAvailable ? state?.state : nil),
          MenuShortcut(key: "p", modifiers: [.command, .shift]),
        ),
        item(.skip, MenuShortcut(key: "k", modifiers: .command)),
        item(.snooze, MenuShortcut(key: "s", modifiers: [.command, .shift])),
      ],
      [
        item(.skipToday, nil),
        item(.newCycle, nil),
        // Lunch is chosen rather than earned, so `TimerActions.available(for:)` — which is the
        // chip row's list — never names it and cannot answer for it. It is enabled wherever there
        // is a daemon to take it, which is every state but lunch itself: the daemon accepts the
        // verb unconditionally (`Core.handleLunch`), and starting a lunch already running would
        // only restart the hour. It binds no key; throwntom-bxd.17 owns what is bound.
        item(.lunch, nil, isEnabled: daemonAvailable && state != nil && state?.state != .lunch),
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
  ///
  /// `daemonAvailable` is asked separately from `state` for the same reason `timer(...)` asks it:
  /// the client goes on holding its last state after the service is gone, so reading `state`
  /// alone would offer durations, and a stale `snoozeUntil` would offer Cancel Snooze, into a
  /// daemon no longer there to answer either.
  static func snooze(state: DaemonState?, daemonAvailable: Bool) -> MenuModel {
    snooze(
      canDefer: daemonAvailable && (state.map { TimerActions.available(for: $0).contains(.snooze) } ?? false),
      isSnoozed: daemonAvailable && state?.snoozeUntil != nil,
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
  static func service(status: ServiceStatus) -> MenuModel {
    MenuModel(groups: [[MenuItem(action: ServiceActions.startOrStop(status: status), shortcut: nil, isEnabled: true)]])
  }
}

extension MenuModel where Action == TaskAction {
  /// The Tasks menu for the current editor state. Every verb but New Task needs a selection,
  /// and the inline new-task row owns the keyboard while it is open. `taskID` names the row the
  /// menu was opened on, which need not be the selected one; passing none reads for the selection.
  /// Every verb — whether it can run, and whether Focus reads as its own undo — answers for that
  /// row, so a context menu on an unselected row does not describe a different task.
  ///
  /// Every verb here is a command line for the daemon, New Task included — the row it opens
  /// exists to send one — so with no daemon there is nothing any of them can do.
  @MainActor
  static func tasks(model: TaskWindowModel, on taskID: Int? = nil, daemonAvailable: Bool) -> MenuModel {
    // Resolved once: whether a verb can run and whether Focus reads as its own undo are two
    // questions about one row, and reading the row twice is how they came to disagree.
    let row = taskID ?? model.selectedID
    let focused = model.isFocused(row)
    func item(_ action: TaskAction, _ key: KeyEquivalent, _ modifiers: EventModifiers) -> MenuItem<TaskAction> {
      MenuItem(
        action: action,
        shortcut: MenuShortcut(key: key, modifiers: modifiers),
        isEnabled: daemonAvailable && model.canPerform(action, on: row),
        title: action.title(focused: focused),
      )
    }
    return MenuModel(groups: [
      [
        item(.newTask, "n", .command),
        item(.complete, .return, .command),
        item(.delete, .delete, .command),
        item(.focus, "f", [.command, .shift]),
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
  ///
  /// Decided per command rather than blanket-disabled. Both panels are daemon-backed — the task
  /// list is fetched and its rows dispatch, the stats summary is fetched — so with no daemon they
  /// open onto nothing. The cheat sheet is local and stays useful; taking it away would punish the
  /// reader for the outage they are trying to understand.
  ///
  /// `showsShortcuts` arrives as a plain answer rather than as the model holding it, because the
  /// cheat sheet asks this menu what would fire once the sheet is out of the way: ⌘/ is the one
  /// command withheld by the sheet's own presence, and the sheet is the only place a reader ever
  /// sees the row for it.
  static func view(showsShortcuts: Bool, daemonAvailable: Bool) -> MenuModel {
    MenuModel(groups: [[
      MenuItem(action: .tasks, shortcut: MenuShortcut(key: "t", modifiers: .command), isEnabled: daemonAvailable),
      MenuItem(
        action: .stats,
        shortcut: MenuShortcut(key: "i", modifiers: [.command, .shift]),
        isEnabled: daemonAvailable,
      ),
      MenuItem(
        action: .shortcuts,
        shortcut: MenuShortcut(key: "/", modifiers: .command),
        isEnabled: !showsShortcuts,
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
  static func windowCommands(model: WindowModel, daemonAvailable: Bool) -> MenuModel {
    MenuModel(groups: [
      view(showsShortcuts: model.showsShortcuts, daemonAvailable: daemonAvailable).items + appConfig().items
    ])
  }
}

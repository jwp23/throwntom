import SwiftUI
import ThrowntomClient

// MARK: - AppMenus

/// Application, Timer, View and Tasks menus. Every action here is also a chip, a row or a panel
/// somewhere; this is where the shortcuts are bound and discoverable.
struct AppMenus: Commands {

  @Environment(\.openWindow) var openWindow

  let environment: AppEnvironment

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      MenuGroups(menu: MenuModel.appConfig()) { item in
        Button(item.title) { show(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
      }
      Divider()
      LoginItemToggle(registrar: environment.registrar)
      Button("Open Login Items Settings…") { environment.registrar.openLoginItemsSettings() }
      Button("Open Notification Settings…") { environment.responder.openNotificationSettings() }
    }
    CommandMenu("Timer") {
      MenuGroups(menu: timerMenu) { item in
        Button(item.title) { perform(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
      // The durations live in a submenu under the Timer menu's own Snooze, which keeps ⌘⇧S on
      // the default and puts every other duration one level down rather than in the top list.
      Menu("Snooze For") {
        MenuGroups(menu: snoozeMenu) { item in
          Button(item.title) { snooze(item.action) }
            .disabled(!item.isEnabled)
        }
      }
      // A submenu whose every item is greyed says the same thing one level up and one click
      // sooner, so the parent goes with them.
      .disabled(!snoozeMenu.items.contains(where: \.isEnabled))
      Divider()
      MenuGroups(menu: serviceMenu) { item in
        Button(item.title) { control(item.action) }
      }
    }
    CommandMenu("View") {
      MenuGroups(menu: viewMenu) { item in
        Button(item.title) { show(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
    }
    CommandMenu("Tasks") {
      MenuGroups(menu: MenuModel.tasks(model: environment.model, daemonAvailable: daemonAvailable)) { item in
        Button(item.title) { run(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
    }
  }

  /// Whether there is a daemon for these menus to dispatch to. Every menu that sends a command
  /// asks it, so the menu bar cannot go on offering a verb the window has already withdrawn.
  var daemonAvailable: Bool {
    environment.client.serviceStatus.offersDaemonCommands
  }

  /// The timer verbs. Their key equivalents fire whether or not the menu is open, which is why
  /// enablement here matters as much as it does in the window: a disabled item binds nothing.
  ///
  /// Confirm is bound to ⇧⏎, and a main menu's key equivalent is offered a keystroke before
  /// whatever has focus ever sees it — so it gives the key up while anything in front of it is
  /// using it. Three surfaces are: the inline new-task row, the custom-snooze duration field, and
  /// the shortcuts sheet, whose Done button is the default action. The shift does not retire this:
  /// a field editor answers Shift-Return too, and a main menu is offered the keystroke first either
  /// way, so what the shift buys is that Confirm no longer sits on the key a default button and a
  /// committing field are *always* on — not any change in the order macOS asks in.
  ///
  /// The snooze field needs this in exactly the state it opens from — `awaiting_confirm` offers
  /// Confirm and Snooze at once, so without it the Return that should have committed a typed
  /// duration confirmed the stage instead, answering the very reminder the user was deferring. The
  /// sheet is worse for being opaque: it covers the window, so a stage confirmed behind it happens
  /// out of sight.
  ///
  /// The guard outlived the rebinding it once stood in for. Confirm keeps ⇧⏎ and hands it back the
  /// moment the surface in front closes.
  var timerMenu: MenuModel<TimerAction> {
    MenuModel.timer(
      state: environment.client.state,
      returnIsTaken: environment.returnIsTaken,
      daemonAvailable: daemonAvailable,
    )
  }

  /// The two panels and the cheat sheet. ⌘/ is withheld while the sheet is already up, so the menu
  /// has to be told whether it is.
  var viewMenu: MenuModel<ViewAction> {
    MenuModel.view(showsShortcuts: environment.windowModel.showsShortcuts, daemonAvailable: daemonAvailable)
  }

  /// The durations behind the Timer menu's Snooze, read twice per build: once for the items and
  /// once to decide whether the submenu itself is worth opening. Gated on `daemonAvailable` the
  /// same way `timerMenu` is: a snooze is a command line for the daemon like any other, and the
  /// client keeps its last retained state after the service is gone, so without this gate the
  /// submenu would go on offering durations — and Cancel Snooze, off a stale `snoozeUntil` — into
  /// a daemon no longer there to answer them.
  var snoozeMenu: MenuModel<SnoozeAction> {
    MenuModel.snooze(state: environment.client.state, daemonAvailable: daemonAvailable)
  }

  /// The service group of the Timer menu, below a divider: starting and stopping the daemon is
  /// not a timer verb, but it belongs to the same menu the timer is driven from.
  var serviceMenu: MenuModel<ServiceAction> {
    MenuModel.service(status: environment.client.serviceStatus)
  }

  func perform(_ action: TimerAction) {
    DaemonDispatch.perform(action, on: environment.client)
  }

  /// `Custom…` opens the window's duration field rather than sending anything, so choosing it
  /// from the menu bar has to put that field in front of the user: a flag set behind a closed
  /// window is a command that appears to do nothing and then ambushes the next person to open it.
  /// `openWindow` is enough. This is the app's main menu, which macOS only lets a user operate
  /// while Throwntom is already frontmost, so the window opens key and `SnoozeEntryRow` focuses
  /// the field itself on appear. Activating would be a no-op here, and throwntom-lbw bans it
  /// where it is not: raising over another app steals the keyboard from whatever is being typed.
  func snooze(_ action: SnoozeAction) {
    guard let request = action.request else {
      environment.windowModel.isEnteringSnooze = true
      openWindow(id: mainWindowID)
      return
    }
    DaemonDispatch.perform(request, on: environment.client)
  }

  func control(_ action: ServiceAction) {
    DaemonDispatch.control(action, on: environment.client)
  }

  func run(_ action: TaskAction) {
    TaskActionDispatch.run(action, environment: environment)
  }

  func show(_ action: ViewAction) {
    ViewActionDispatch.show(action, in: environment.windowModel)
  }

}

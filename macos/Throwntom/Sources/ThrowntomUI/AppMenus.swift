import SwiftUI
import ThrowntomClient

// MARK: - AppMenus

/// Application, Timer, View and Tasks menus. Every action here is also a chip, a row or a panel
/// somewhere; this is where the shortcuts are bound and discoverable.
struct AppMenus: Commands {

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
      Divider()
      MenuGroups(menu: serviceMenu) { item in
        Button(item.title) { control(item.action) }
      }
    }
    CommandMenu("View") {
      MenuGroups(menu: MenuModel.view(model: environment.windowModel, daemonAvailable: daemonAvailable)) { item in
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
  var timerMenu: MenuModel<TimerAction> {
    MenuModel.timer(
      state: environment.client.state,
      isEditing: environment.model.isEditing,
      daemonAvailable: daemonAvailable,
    )
  }

  /// The service group of the Timer menu, below a divider: starting and stopping the daemon is
  /// not a timer verb, but it belongs to the same menu the timer is driven from.
  var serviceMenu: MenuModel<ServiceAction> {
    MenuModel.service(status: environment.client.serviceStatus)
  }

  func perform(_ action: TimerAction) {
    DaemonDispatch.perform(action, on: environment.client)
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

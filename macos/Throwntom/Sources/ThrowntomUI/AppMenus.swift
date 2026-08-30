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
      MenuGroups(menu: MenuModel.timer(state: environment.client.state, isEditing: environment.model.isEditing)) { item in
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
      MenuGroups(menu: MenuModel.view(model: environment.windowModel)) { item in
        Button(item.title) { show(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
    }
    CommandMenu("Tasks") {
      MenuGroups(menu: MenuModel.tasks(model: environment.model)) { item in
        Button(item.title) { run(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
    }
  }

  /// The service group of the Timer menu, below a divider: starting and stopping the daemon is
  /// not a timer verb, but it belongs to the same menu the timer is driven from.
  var serviceMenu: MenuModel<ServiceAction> {
    MenuModel.service(
      connection: environment.client.connection,
      registrationFailed: environment.client.registrationError != nil,
    )
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

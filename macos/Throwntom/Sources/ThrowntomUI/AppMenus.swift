import SwiftUI
import ThrowntomClient

// MARK: - ConfigFile

enum ConfigFile {
  static func open() {
    NSWorkspace.shared.open(DaemonPaths.configFileToOpen())
  }
}

// MARK: - AppMenus

/// Application, Timer, View and Tasks menus. Every action here is also a chip, a row or a panel
/// somewhere; this is where the shortcuts are bound and discoverable.
struct AppMenus: Commands {

  let environment: AppEnvironment

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Open Config File…") { ConfigFile.open() }.keyboardShortcut(",")
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

  func perform(_ action: TimerAction) {
    DaemonDispatch.perform(action, on: environment.client)
  }

  func run(_ action: TaskAction) {
    TaskActionDispatch.run(action, environment: environment)
  }

  func show(_ action: ViewAction) {
    if let panel = action.panel {
      environment.windowModel.toggle(panel)
    } else {
      environment.windowModel.showsShortcuts = true
    }
  }

}

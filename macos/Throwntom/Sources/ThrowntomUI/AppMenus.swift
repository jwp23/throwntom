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

  // MARK: Internal

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
      menu(MenuModel.timer(state: environment.client.state, isEditing: environment.model.isEditing), run: perform)
    }
    CommandMenu("View") {
      menu(MenuModel.view(model: environment.windowModel), run: show)
    }
    CommandMenu("Tasks") {
      menu(MenuModel.tasks(model: environment.model), run: run)
    }
  }

  func perform(_ action: TimerAction) {
    DaemonDispatch.perform(action, on: environment.client)
  }

  /// New Task opens the inline editor; every other verb is a command line for the selection.
  func run(_ action: TaskAction) {
    if action == .newTask {
      environment.windowModel.panel = .tasks
      environment.model.beginNewTask()
    } else if let line = environment.model.command(for: action) {
      DaemonDispatch.send(line, to: environment.client)
    }
  }

  func show(_ action: ViewAction) {
    if let panel = action.panel {
      environment.windowModel.toggle(panel)
    } else {
      environment.windowModel.showsShortcuts = true
    }
  }

  // MARK: Private

  private func menu<Action>(_ menu: MenuModel<Action>, run: @escaping (Action) -> Void) -> some View {
    ForEach(Array(menu.groups.enumerated()), id: \.offset) { index, group in
      if index > 0 {
        Divider()
      }
      ForEach(group) { item in
        Button(item.title) { run(item.action) }
          .keyboardShortcut(item.shortcut?.keyboardShortcut)
          .disabled(!item.isEnabled)
      }
    }
  }

}

import SwiftUI
import ThrowntomClient

enum ConfigFile {
    static func open() {
        NSWorkspace.shared.open(DaemonPaths.configFileToOpen())
    }
}

/// Timer and Tasks menus; every action here is also a button somewhere, this is where shortcuts are discoverable.
struct AppMenus: Commands {
    let client: DaemonClient
    let model: TaskWindowModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Open Config File…") { ConfigFile.open() }.keyboardShortcut(",")
        }
        CommandMenu("Timer") {
            menu(MenuModel.timer(state: client.state, isEditing: model.isEditing), run: perform)
        }
        CommandMenu("Tasks") {
            menu(MenuModel.tasks(model: model), run: run)
        }
    }

    @ViewBuilder
    private func menu<Action>(_ menu: MenuModel<Action>, run: @escaping (Action) -> Void) -> some View {
        ForEach(Array(menu.groups.enumerated()), id: \.offset) { index, group in
            if index > 0 { Divider() }
            ForEach(group) { item in
                Button(item.title) { run(item.action) }
                    .keyboardShortcut(item.shortcut?.keyboardShortcut)
                    .disabled(!item.isEnabled)
            }
        }
    }

    func perform(_ action: TimerAction) {
        Task {
            do { try await client.perform(action) } catch { NSSound.beep() }
        }
    }

    /// New Task opens the inline editor; every other verb is a command line for the selection.
    func run(_ action: TaskAction) {
        if action == .newTask {
            model.beginNewTask()
        } else if let line = model.command(for: action) {
            send(line)
        }
    }

    private func send(_ line: String) {
        Task {
            do { _ = try await client.command(line) } catch { NSSound.beep() }
        }
    }
}

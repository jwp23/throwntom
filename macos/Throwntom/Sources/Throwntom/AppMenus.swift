import SwiftUI
import ThrowntomClient

enum ConfigFile {
    static func open() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/throwntom")
        let file = dir.appendingPathComponent("config.toml")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: file.path) ? file : dir)
    }
}

/// Timer and Tasks menus; every action here is also a button somewhere, this is where shortcuts are discoverable.
struct AppMenus: Commands {
    let client: DaemonClient
    let model: TaskWindowModel

    private var phase: DaemonState.Phase? { client.state?.state }
    private var available: [TimerAction] { client.state.map(TimerActions.available(for:)) ?? [] }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Open Config File…") { ConfigFile.open() }.keyboardShortcut(",")
        }
        CommandMenu("Timer") {
            timerItem(.start, key: "r", modifiers: .command)
            timerItem(.confirm, key: .return, modifiers: [])
                .disabled(!available.contains(.confirm) || model.isEditing)
            if phase == .paused {
                timerItem(.resume, key: "p", modifiers: .command)
            } else {
                timerItem(.pause, key: "p", modifiers: .command)
            }
            timerItem(.snooze, key: "s", modifiers: [.command, .shift])
            Divider()
            Button(TimerAction.skipToday.title) { perform(.skipToday) }.disabled(!available.contains(.skipToday))
            Button(TimerAction.newCycle.title) { perform(.newCycle) }.disabled(!available.contains(.newCycle))
        }
        CommandMenu("Tasks") {
            Button(TaskAction.newTask.title) { model.beginNewTask() }
                .keyboardShortcut("n").disabled(!model.canPerform(.newTask))
            taskItem(.complete, key: .return, modifiers: .command)
            taskItem(.delete, key: .delete, modifiers: .command)
            taskItem(.focus, key: "f", modifiers: .command)
            Divider()
            taskItem(.moveUp, key: .upArrow, modifiers: .option)
            taskItem(.moveDown, key: .downArrow, modifiers: .option)
        }
    }

    private func timerItem(_ action: TimerAction, key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        Button(action.title) { perform(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!available.contains(action))
    }

    private func taskItem(_ action: TaskAction, key: KeyEquivalent, modifiers: EventModifiers) -> some View {
        Button(action.title) {
            if let line = model.command(for: action) { send(line) }
        }
        .keyboardShortcut(key, modifiers: modifiers)
        .disabled(!model.canPerform(action))
    }

    private func perform(_ action: TimerAction) {
        Task {
            do {
                if let verb = action.verb {
                    try await client.timer(verb)
                } else {
                    try await client.snooze(minutes: TimerActions.defaultSnoozeMinutes)
                }
            } catch {
                NSSound.beep()
            }
        }
    }

    private func send(_ line: String) {
        Task {
            do { _ = try await client.command(line) } catch { NSSound.beep() }
        }
    }
}

import SwiftUI
import ThrowntomClient

struct PopoverView: View {
    let client: DaemonClient
    let ticker: Ticker
    let registrar: SMAppServiceRegistrar

    @State private var loginItem = false
    @State private var registrarMessage: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MenuBarTitle.text(state: client.state, connection: client.connection, now: ticker.now))
                .font(.headline)
            if let state = client.state {
                if let next = state.nextStage {
                    Text("Next: \(phaseName(next.state)) \(next.duration / 60) min").foregroundStyle(.secondary)
                }
                focusedTasks(state)
                Divider()
                ForEach(TimerActions.available(for: state), id: \.self) { action in
                    TimerActionButton(action: action, client: client)
                }
            }
            if let error = client.lastError, client.connection != .connected {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            Button("Open Tasks…") {
                NSApp.activate()
                openWindow(id: taskWindowID)
            }
            .keyboardShortcut("t")
            Divider()
            Toggle("Launch at login", isOn: $loginItem)
                .onChange(of: loginItem) { _, enabled in setLoginItem(enabled) }
            Text(registrarMessage ?? registrar.agentStatusDescription).font(.caption).foregroundStyle(.secondary)
            Button("Open Login Items Settings…") { registrar.openLoginItemsSettings() }
            Button("Quit Throwntom") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { loginItem = registrar.loginItemEnabled }
    }

    @ViewBuilder
    private func focusedTasks(_ state: DaemonState) -> some View {
        let focused = client.tasks.active.filter { state.focusedTaskIds.contains($0.id) }
        if !focused.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus").font(.caption).foregroundStyle(.secondary)
                ForEach(focused) { Text("• \($0.description)") }
            }
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try registrar.setLoginItem(enabled)
            registrarMessage = nil
        } catch {
            registrarMessage = "Login item: \(error.localizedDescription)"
            loginItem = registrar.loginItemEnabled
        }
    }

    private func phaseName(_ phase: DaemonState.Phase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .work: return "Pomodoro"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        case .awaitingConfirm: return "Confirm"
        case .paused: return "Paused"
        }
    }
}

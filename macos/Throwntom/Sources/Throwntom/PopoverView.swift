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
            Text(ConnectionStatus.text(state: client.state, connection: client.connection, now: ticker.now))
                .font(.headline)
            if let state = client.state {
                if let next = state.nextStage {
                    Text("Next: \(next.summary)").foregroundStyle(.secondary)
                }
                focusedTasks(state)
                Divider()
                ForEach(TimerActions.available(for: state), id: \.self) { action in
                    TimerActionButton(action: action, client: client)
                }
            }
            if let error = client.unresolvedError {
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
        let focused = client.tasks.focused(ids: state.focusedTaskIds)
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
}

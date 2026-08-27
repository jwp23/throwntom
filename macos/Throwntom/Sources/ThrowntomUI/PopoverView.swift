import SwiftUI
import ThrowntomClient

struct PopoverView: View {
    let client: DaemonClient
    let ticker: Ticker
    let registrar: SMAppServiceRegistrar
    let responder: ReminderResponder

    @State private var loginItem = LoginItemSetting(isOn: false, message: nil)
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
                PopoverCaption(text: error)
            }
            if let problem = responder.authorization.problem {
                PopoverCaption(text: problem)
                Button("Open Notification Settings…") { responder.openNotificationSettings() }
            }
            Divider()
            Button("Open Tasks…") {
                NSApp.activate()
                openWindow(id: taskWindowID)
            }
            .keyboardShortcut("t")
            Divider()
            Toggle("Launch at login", isOn: $loginItem.isOn)
                .onChange(of: loginItem.isOn) { _, enabled in setLoginItem(enabled) }
            Text(loginItem.message ?? registrar.agentStatusDescription).font(.caption).foregroundStyle(.secondary)
            Button("Open Login Items Settings…") { registrar.openLoginItemsSettings() }
            Button("Quit Throwntom") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { loginItem.isOn = registrar.loginItemEnabled }
        .task { await responder.refreshAuthorization() }
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
        loginItem = .afterSetting(enabled, in: registrar)
    }
}

/// A note under the popover's controls. Its text is a sentence rather than a label, so it wraps to
/// as many lines as it needs: at the popover's width a daemon error or a permission warning runs
/// past two lines, and truncating it hides the part that says what to do.
struct PopoverCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

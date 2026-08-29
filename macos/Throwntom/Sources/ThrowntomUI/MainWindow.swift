import SwiftUI
import ThrowntomClient

let mainWindowID = "main"

// MARK: - MainWindow

/// The whole app: phase-coloured ground, timer header, garden, chips, notes, focus, and the
/// optional panel. Everything it shows is decided by `MainWindowContent`.
struct MainWindow: View {

  let environment: AppEnvironment

  var body: some View {
    let content = MainWindowContent(
      state: environment.client.state,
      connection: environment.client.connection,
      tasks: environment.client.tasks,
      error: environment.client.unresolvedError,
      panel: environment.windowModel.panel,
      now: environment.ticker.now,
    )
    VStack(spacing: 12) {
      TimerHeader(content: content)
      if let garden = content.garden {
        TomatoGardenView(garden: garden)
      }
      ActionChips(content: content, client: environment.client)
      WindowNotes(error: content.error, responder: environment.responder)
      FocusSection(tasks: content.focused)
      if content.panel == .tasks {
        TasksPanel(environment: environment, scheme: content.scheme)
      }
      if content.panel == .stats {
        StatsPanel(client: environment.client, scheme: content.scheme)
      }
    }
    .padding(16)
    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(content.scheme.ground.color)
    .foregroundStyle(content.scheme.text.color)
    .animation(.easeOut(duration: 0.25), value: content.scheme)
    .animation(.easeOut(duration: 0.25), value: content.panel)
    .onExitCommand { escape() }
    .sheet(isPresented: Bindable(environment.windowModel).showsShortcuts) {
      ShortcutSheet(environment: environment)
    }
    .onChange(of: environment.client.tasks, initial: true) { syncModel() }
    .onChange(of: environment.client.state?.focusedTaskIds, initial: true) { syncModel() }
    .task { await trackAuthorization() }
  }

  /// Reads the notification permission now and again whenever the user comes back, so granting it
  /// in System Settings clears the note without a relaunch.
  func trackAuthorization() async {
    await environment.responder.refreshAuthorization()
    let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification)
    for await _ in activations {
      await environment.responder.refreshAuthorization()
    }
  }

  /// Copies the daemon's task list and focus into the model the list and menus read from.
  func syncModel() {
    environment.model.sync(tasks: environment.client.tasks, focusedTaskIDs: environment.client.state?.focusedTaskIds)
  }

  /// Escape closes whatever is open on top first; with nothing open it cancels a task edit.
  func escape() {
    if !environment.windowModel.dismiss() {
      environment.model.cancelEdit()
    }
  }

}

import SwiftUI
import ThrowntomClient

/// The menu bar item and the task window. Kept out of `ThrowntomApp` so the scene graph can be
/// built from a test-owned environment instead of the live one the app lifecycle installs.
struct ThrowntomScenes: Scene {
    let environment: AppEnvironment

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                client: environment.client,
                ticker: environment.ticker,
                registrar: environment.registrar,
                responder: environment.responder)
        } label: {
            Text(ConnectionStatus.text(
                state: environment.client.state,
                connection: environment.client.connection,
                now: environment.ticker.now))
        }
        .menuBarExtraStyle(.window)

        Window("Tasks", id: taskWindowID) {
            TaskWindow(client: environment.client, model: environment.model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 420, height: 360)
        .commands { AppMenus(client: environment.client, model: environment.model) }
    }
}

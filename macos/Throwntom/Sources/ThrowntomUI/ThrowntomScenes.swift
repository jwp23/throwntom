import SwiftUI
import ThrowntomClient

/// The one window. Kept out of `ThrowntomApp` so the scene graph can be built from a test-owned
/// environment instead of the live one the app lifecycle installs.
struct ThrowntomScenes: Scene {
  let environment: AppEnvironment

  var body: some Scene {
    Window("Throwntom", id: mainWindowID) {
      MainWindow(environment: environment)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 360, height: 420)
    .commands { AppMenus(environment: environment) }
  }
}

import AppKit
import ThrowntomClient

// MARK: - ConfigFile

/// The TOML the daemon reads, opened in whatever the user edits text with.
enum ConfigFile {
  static func open() {
    NSWorkspace.shared.open(DaemonPaths.configFileToOpen())
  }
}

// MARK: - ViewActionDispatch

/// Runs a `ViewAction`, so the menu bar and the window's chips do the same thing.
enum ViewActionDispatch {
  @MainActor
  static func show(_ action: ViewAction, in model: WindowModel) {
    switch action {
    case .tasks,
         .stats:
      if let panel = action.panel {
        model.toggle(panel)
      }

    case .shortcuts:
      model.showsShortcuts = true

    case .openConfig:
      ConfigFile.open()
    }
  }
}

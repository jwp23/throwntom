import Observation

// MARK: - WindowPanel

/// The optional section under the timer: the full task list or the stats summary.
enum WindowPanel: Equatable, Sendable {
  case tasks
  case stats
}

// MARK: - ViewAction

/// The commands that show something: the two panels, the cheat sheet and the config file. The
/// first three are the View menu; the config file lives in the app menu, where macOS puts ⌘,.
/// All four are chips in the window, so none of them is reachable only from the menu bar.
enum ViewAction: CaseIterable, Sendable {
  case tasks
  case stats
  case shortcuts
  case openConfig

  // MARK: Internal

  var title: String {
    switch self {
    case .tasks: "Tasks"
    case .stats: "Stats"
    case .shortcuts: "Keyboard Shortcuts"
    case .openConfig: "Open Config File…"
    }
  }

  var shortcutHint: String {
    switch self {
    case .tasks: "⌘T"
    case .stats: "⌘⇧I"
    case .shortcuts: "⌘/"
    case .openConfig: "⌘,"
    }
  }

  var panel: WindowPanel? {
    switch self {
    case .tasks: .tasks
    case .stats: .stats
    case .shortcuts,
         .openConfig: nil
    }
  }
}

// MARK: - WindowModel

/// Which optional surfaces are showing. Panels start closed on every launch.
@Observable
@MainActor
final class WindowModel {
  var panel: WindowPanel?
  var showsShortcuts = false

  func toggle(_ panel: WindowPanel) {
    self.panel = self.panel == panel ? nil : panel
  }

  /// Escape: the sheet goes first, then the panel. False when nothing was open, which is what
  /// lets the caller fall through to cancelling a task edit.
  ///
  /// `panelIsShown` is asked rather than assumed because the window declines to draw a panel while
  /// the timer service is down, without the model forgetting it. Closing something invisible would
  /// eat the keystroke and never reach the edit cancel behind it.
  func dismiss(panelIsShown: Bool) -> Bool {
    if showsShortcuts {
      showsShortcuts = false
      return true
    }
    if panel != nil, panelIsShown {
      panel = nil
      return true
    }
    return false
  }
}

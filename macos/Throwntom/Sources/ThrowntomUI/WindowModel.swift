import Observation

// MARK: - WindowPanel

/// The optional section under the timer: the full task list or the stats summary.
enum WindowPanel: Equatable, Sendable {
  case tasks
  case stats
}

// MARK: - ViewAction

/// The View menu: which panel is open, plus the shortcut cheat sheet.
enum ViewAction: CaseIterable, Sendable {
  case tasks
  case stats
  case shortcuts

  // MARK: Internal

  var title: String {
    switch self {
    case .tasks: "Tasks"
    case .stats: "Stats"
    case .shortcuts: "Keyboard Shortcuts"
    }
  }

  var shortcutHint: String {
    switch self {
    case .tasks: "⌘T"
    case .stats: "⌘⇧D"
    case .shortcuts: "⌘/"
    }
  }

  var panel: WindowPanel? {
    switch self {
    case .tasks: .tasks
    case .stats: .stats
    case .shortcuts: nil
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

  /// Escape: the sheet goes first, then the panel. False when nothing was open.
  func dismiss() -> Bool {
    if showsShortcuts {
      showsShortcuts = false
      return true
    }
    if panel != nil {
      panel = nil
      return true
    }
    return false
  }
}

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

  /// When this command is on offer, in words, for the cheat sheet — see `TimerAction.availability`.
  /// Both panels are daemon-backed and open onto nothing without one; the cheat sheet and the
  /// config file are local, so they name no condition and are the two rows never dimmed.
  var availability: String {
    switch self {
    case .tasks,
         .stats: "while the timer service is running"
    case .shortcuts,
         .openConfig: ""
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
  /// Whether the snooze chip's "Custom…" duration field is open. Closed on every launch, and
  /// closed again the moment a duration is accepted or abandoned.
  var isEnteringSnooze = false
  /// Whether the meeting chip's "Custom…" length field is open. Closed on every launch, and
  /// closed again the moment a length is accepted or abandoned.
  var isEnteringMeeting = false

  func toggle(_ panel: WindowPanel) {
    self.panel = self.panel == panel ? nil : panel
  }

  /// Escape: the duration field first, then the sheet, then the panel. False when nothing was
  /// open. Innermost first, so Escape always answers whatever the user is looking at.
  ///
  /// `panelIsShown` is asked rather than assumed because the window declines to draw a panel while
  /// the timer service is down, without the model forgetting it. Closing something invisible would
  /// eat the keystroke and never reach the edit cancel behind it.
  func dismiss(panelIsShown: Bool) -> Bool {
    if isEnteringSnooze {
      isEnteringSnooze = false
      return true
    }
    if isEnteringMeeting {
      isEnteringMeeting = false
      return true
    }
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

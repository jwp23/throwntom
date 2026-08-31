public enum TaskAction: CaseIterable, Sendable {
  case newTask
  case complete
  case delete
  case focus
  case moveUp
  case moveDown

  // MARK: Public

  public var title: String {
    switch self {
    case .newTask: "New Task"
    case .complete: "Complete"
    case .delete: "Delete"
    case .focus: "Focus"
    case .moveUp: "Move Up"
    case .moveDown: "Move Down"
    }
  }

  public var shortcutHint: String {
    switch self {
    case .newTask: "⌘N"
    case .complete: "⌘⏎"
    case .delete: "⌘⌫"
    case .focus: "⌘F"
    case .moveUp: "⌥↑"
    case .moveDown: "⌥↓"
    }
  }

  /// Focus is a toggle, so on an already-focused task the verb is the undo. Every other verb
  /// reads the same whatever the task's focus state.
  public func title(focused: Bool) -> String {
    self == .focus && focused ? "Unfocus" : title
  }
}

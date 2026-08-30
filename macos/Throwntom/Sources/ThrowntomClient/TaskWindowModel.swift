import Foundation
import Observation

/// UI state of the tasks panel: the selected row and the in-progress new-task row. Everything else is daemon state.
@Observable @MainActor
public final class TaskWindowModel {

  // MARK: Lifecycle

  public init() {
    // No initialization needed: every stored property has a declared default
    // (empty task list, no selection).
  }

  // MARK: Public

  public private(set) var tasks = TaskList()
  public private(set) var focusedIDs = Set<Int>()
  public var selectedID: Int?
  /// Text of the inline new-task row; nil when the row is closed.
  public var draft: String?

  public var isEditing: Bool {
    draft != nil
  }

  /// Whether the selected task is one of the focused ones; false when nothing is selected.
  public var isSelectedFocused: Bool {
    isFocused(selectedID)
  }

  /// Label of the collapsed completed section, e.g. "Completed (3)".
  public var completedSectionTitle: String {
    "Completed (\(tasks.completed.count))"
  }

  /// Whether a named task is one of the focused ones. No task named is no focus.
  public func isFocused(_ id: Int?) -> Bool {
    id.map(focusedIDs.contains) ?? false
  }

  /// Applies fresh daemon state, keeping the selection on the same task when it still exists.
  /// No focus list at all — no daemon state yet — means nothing is focused.
  public func sync(tasks: TaskList, focusedTaskIDs: [Int]?) {
    self.tasks = tasks
    focusedIDs = Set(focusedTaskIDs ?? [])
    if let id = selectedID, tasks.active.contains(where: { $0.id == id }) {
      return
    }
    selectedID = tasks.active.first?.id
  }

  public func moveSelection(by offset: Int) {
    let ids = tasks.active.map(\.id)
    guard !ids.isEmpty else { return }
    let current = selectedID.flatMap { ids.firstIndex(of: $0) } ?? 0
    selectedID = ids[min(max(current + offset, 0), ids.count - 1)]
  }

  public func beginNewTask() {
    draft = ""
  }

  public func cancelEdit() {
    draft = nil
  }

  /// Closes the row and returns the add command, or nil when the draft was blank.
  public func commitNewTask() throws -> String? {
    defer { draft = nil }
    guard let text = draft else { return nil }
    do {
      return try TaskCommands.addTask(text)
    } catch TaskCommandError.emptyDescription {
      return nil
    }
  }

  /// Whether an action can run on a task. `id` names the row the question is about — a context
  /// menu asks about the row it was opened on; passing none asks about the selected row.
  public func canPerform(_ action: TaskAction, on id: Int? = nil) -> Bool {
    if isEditing {
      return false
    }
    if action == .newTask {
      return true
    }
    return (id ?? selectedID).flatMap { TaskCommands.position(of: $0, in: tasks) } != nil
  }

  /// Command string for an action on the selected task; nil when the action cannot run right now.
  public func command(for action: TaskAction) -> String? {
    guard
      action != .newTask, canPerform(action),
      let id = selectedID, let position = TaskCommands.position(of: id, in: tasks)
    else { return nil }
    return TaskCommands.line(for: action, position: position, focused: focusedIDs.contains(id))
  }

}

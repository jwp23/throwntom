import Foundation
import Observation

/// UI state of the task window: the selected row and the in-progress new-task row. Everything else is daemon state.
@Observable @MainActor
public final class TaskWindowModel {
    public private(set) var tasks = TaskList()
    public private(set) var focusedIDs: Set<Int> = []
    public var selectedID: Int?
    /// Text of the inline new-task row; nil when the row is closed.
    public var draft: String?

    /// Empty: all state starts at its declared default (empty task list, no selection).
    public init() {}

    public var isEditing: Bool { draft != nil }

    /// Applies fresh daemon state, keeping the selection on the same task when it still exists.
    public func sync(tasks: TaskList, focusedIDs: Set<Int>) {
        self.tasks = tasks
        self.focusedIDs = focusedIDs
        if let id = selectedID, tasks.active.contains(where: { $0.id == id }) { return }
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

    public func canPerform(_ action: TaskAction) -> Bool {
        if isEditing { return false }
        if action == .newTask { return true }
        return selectedID.flatMap { TaskCommands.position(of: $0, in: tasks) } != nil
    }

    /// Command string for an action on the selected task; nil when the action cannot run right now.
    public func command(for action: TaskAction) -> String? {
        guard action != .newTask, canPerform(action),
              let id = selectedID, let position = TaskCommands.position(of: id, in: tasks) else { return nil }
        return TaskCommands.line(for: action, position: position, focused: focusedIDs.contains(id))
    }
}

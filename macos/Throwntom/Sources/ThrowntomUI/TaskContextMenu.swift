import SwiftUI
import ThrowntomClient

// MARK: - TaskHints

/// The one-line reminder under the task list. Assembled from the actions' own hints.
enum TaskHints {
  static let line = [
    "\(TaskAction.newTask.shortcutHint) new",
    "\(TaskAction.complete.shortcutHint) done",
    "\(TaskAction.focus.shortcutHint) focus",
    "\(TaskAction.moveUp.shortcutHint)\(TaskAction.moveDown.shortcutHint.suffix(1)) move",
    "\(TaskAction.delete.shortcutHint) delete",
  ].joined(separator: " · ")
}

// MARK: - TaskContextMenu

/// Right-click on a task row: every task verb, with its shortcut, applied to that row.
struct TaskContextMenu: View {

  let task: TaskItem
  let client: DaemonClient
  let model: TaskWindowModel

  var body: some View {
    let menu = MenuModel.tasks(model: model)
    ForEach(Array(menu.groups.enumerated()), id: \.offset) { index, group in
      if index > 0 {
        Divider()
      }
      ForEach(group) { item in
        Button("\(item.title)  \(item.action.shortcutHint)") { run(item.action) }
          .disabled(!item.isEnabled)
      }
    }
  }

  /// Selects the row the menu was opened on, then behaves exactly like the Tasks menu.
  func run(_ action: TaskAction) {
    model.selectedID = task.id
    if action == .newTask {
      model.beginNewTask()
    } else if let line = model.command(for: action) {
      DaemonDispatch.send(line, to: client)
    }
  }

}

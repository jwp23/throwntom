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

  /// Stands in for the list when there is nothing to act on, so the panel is never blank. It
  /// names the only verb that applies, which is why the full hint line stays away until there
  /// is a task to run the other verbs on.
  static let empty = "No tasks — \(TaskAction.newTask.shortcutHint) to add one"
}

// MARK: - TaskContextMenu

/// Right-click on a task row: every task verb, with its shortcut, applied to that row.
struct TaskContextMenu: View {

  let task: TaskItem
  let environment: AppEnvironment

  /// The verbs read for the row the menu was opened on, which need not be the selected one.
  var menu: MenuModel<TaskAction> {
    MenuModel.tasks(
      model: environment.model,
      on: task.id,
      daemonAvailable: environment.client.serviceStatus.offersDaemonCommands,
    )
  }

  var body: some View {
    MenuGroups(menu: menu) { item in
      Button("\(item.title)  \(item.action.shortcutHint)") { run(item.action) }
        .disabled(!item.isEnabled)
    }
  }

  /// Selects the row the menu was opened on, then behaves exactly like the Tasks menu.
  func run(_ action: TaskAction) {
    environment.model.selectedID = task.id
    TaskActionDispatch.run(action, environment: environment)
  }

}

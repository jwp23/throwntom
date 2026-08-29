import ThrowntomClient

/// What choosing a task verb does, whether from the Tasks menu or a row's context menu: New Task
/// opens the panel and the inline editor; every other verb is a command line for the selection.
enum TaskActionDispatch {
  @MainActor
  static func run(_ action: TaskAction, environment: AppEnvironment) {
    if action == .newTask {
      environment.windowModel.panel = .tasks
      environment.model.beginNewTask()
    } else if let line = environment.model.command(for: action) {
      DaemonDispatch.send(line, to: environment.client)
    }
  }
}

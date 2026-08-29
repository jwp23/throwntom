import SwiftUI
import ThrowntomClient

/// The full task list, opened under the timer with ⌘T: active tasks, then completed ones in a
/// collapsed group. Selection and the inline editor live in `TaskWindowModel`.
struct TasksPanel: View {

  // MARK: Lifecycle

  init(environment: AppEnvironment, scheme: PhaseScheme) {
    self.environment = environment
    _model = Bindable(environment.model)
    self.scheme = scheme
  }

  // MARK: Internal

  @Bindable var model: TaskWindowModel

  let environment: AppEnvironment

  let scheme: PhaseScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Tasks").font(.caption).textCase(.uppercase)
      List(selection: $model.selectedID) {
        if model.isEditing {
          NewTaskRow(model: model) { line in DaemonDispatch.send(line, to: environment.client) }
        }
        ForEach(model.tasks.active) { task in
          TaskRow(task: task, focused: model.focusedIDs.contains(task.id))
            .tag(task.id)
            .contextMenu { TaskContextMenu(task: task, environment: environment) }
        }
        if !model.tasks.completed.isEmpty {
          DisclosureGroup(model.completedSectionTitle, isExpanded: $showCompleted) {
            ForEach(model.tasks.completed) { task in
              TaskRow(task: task, focused: false)
            }
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .frame(minHeight: 160, maxHeight: 280)
      Text(TaskHints.line).font(.body.monospaced())
    }
    .padding(10)
    .foregroundStyle(scheme.panelText.color)
    .background(scheme.panel.color, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: Private

  @State private var showCompleted = false

}

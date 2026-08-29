import SwiftUI
import ThrowntomClient

/// The full task list, opened under the timer with ⌘T: active tasks, then completed ones in a
/// collapsed group. Selection and the inline editor live in `TaskWindowModel`.
struct TasksPanel: View {

  // MARK: Internal

  let client: DaemonClient
  @Bindable var model: TaskWindowModel

  let scheme: PhaseScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Tasks").font(.caption).textCase(.uppercase).opacity(0.8)
      List(selection: $model.selectedID) {
        if model.isEditing {
          NewTaskRow(model: model) { line in DaemonDispatch.send(line, to: client) }
        }
        ForEach(model.tasks.active) { task in
          TaskRow(task: task, focused: model.focusedIDs.contains(task.id))
            .tag(task.id)
            .contextMenu { TaskContextMenu(task: task, client: client, model: model) }
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
      Text(TaskHints.line).font(.caption.monospaced()).opacity(0.75)
    }
    .padding(10)
    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: Private

  @State private var showCompleted = false

}

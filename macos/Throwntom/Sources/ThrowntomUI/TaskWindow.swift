import SwiftUI
import ThrowntomClient

let taskWindowID = "tasks"

// MARK: - TaskWindow

struct TaskWindow: View {

  // MARK: Internal

  let client: DaemonClient
  let model: TaskWindowModel

  var body: some View {
    let content = TaskWindowContent(state: client.state, connection: client.connection, model: model, now: .now)
    List(selection: Binding(get: { model.selectedID }, set: { model.selectedID = $0 })) {
      if content.isEditing {
        NewTaskRow(model: model) { line in send(line) }
      }
      ForEach(content.active) { task in
        TaskRow(task: task, focused: content.focusedIDs.contains(task.id)).tag(task.id)
      }
      if let completed = content.completed {
        DisclosureGroup(completed.title, isExpanded: $showCompleted) {
          ForEach(completed.tasks) { task in
            TaskRow(task: task, focused: false)
          }
        }
      }
    }
    .listStyle(.inset)
    .overlay {
      if let text = content.placeholder {
        ContentUnavailableView(text, systemImage: "bolt.horizontal.circle")
      }
    }
    .frame(minWidth: 360, minHeight: 240)
    .toolbar {
      ForEach(content.toolbarActions, id: \.self) { action in
        TimerActionButton(action: action, client: client, layout: .toolbar)
      }
    }
    .onChange(of: client.tasks, initial: true) { syncModel() }
    .onChange(of: client.state?.focusedTaskIds, initial: true) { syncModel() }
  }

  /// Copies the daemon's task list and focus into the model the list and menus read from.
  /// No focus list at all — no daemon state yet — means nothing is focused.
  func syncModel() {
    model.sync(tasks: client.tasks, focusedTaskIDs: client.state?.focusedTaskIds)
  }

  /// Sends a command line to the daemon; a refusal beeps, the list updates from the event stream.
  func send(_ line: String) {
    Task {
      do { _ = try await client.command(line) } catch { NSSound.beep() }
    }
  }

  // MARK: Private

  @State private var showCompleted = false

}

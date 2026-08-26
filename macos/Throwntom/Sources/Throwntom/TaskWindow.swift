import SwiftUI
import ThrowntomClient

let TaskWindowID = "tasks"

struct TaskWindow: View {
    let client: DaemonClient
    let model: TaskWindowModel

    @State private var showCompleted = false

    var body: some View {
        List(selection: Binding(get: { model.selectedID }, set: { model.selectedID = $0 })) {
            if model.isEditing {
                NewTaskRow(model: model) { line in send(line) }
            }
            ForEach(model.tasks.active) { task in
                TaskRow(task: task, focused: model.focusedIDs.contains(task.id)).tag(task.id)
            }
            if !model.tasks.completed.isEmpty {
                DisclosureGroup("Completed (\(model.tasks.completed.count))", isExpanded: $showCompleted) {
                    ForEach(model.tasks.completed) { task in
                        TaskRow(task: task, focused: false)
                    }
                }
            }
        }
        .listStyle(.inset)
        .frame(minWidth: 360, minHeight: 240)
        .toolbar {
            if let state = client.state {
                ForEach(TimerActions.available(for: state), id: \.self) { action in
                    TimerActionButton(action: action, client: client)
                }
            }
        }
        .onChange(of: client.tasks, initial: true) { syncModel() }
        .onChange(of: client.state?.focusedTaskIds, initial: true) { syncModel() }
    }

    private func syncModel() {
        model.sync(tasks: client.tasks, focusedIDs: Set(client.state?.focusedTaskIds ?? []))
    }

    /// Sends a command line to the daemon; a refusal beeps, the list updates from the event stream.
    func send(_ line: String) {
        Task {
            do { _ = try await client.command(line) } catch { NSSound.beep() }
        }
    }
}

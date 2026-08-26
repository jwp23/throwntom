import SwiftUI
import ThrowntomClient

/// Inline editor inserted above the active tasks while a new task is being typed.
struct NewTaskRow: View {
    let model: TaskWindowModel
    let onCommit: (String) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("New task", text: Binding(
            get: { model.draft ?? "" },
            set: { model.draft = $0 }))
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { commit() }
            .onExitCommand { model.cancelEdit() }
    }

    private func commit() {
        do {
            if let line = try model.commitNewTask() { onCommit(line) }
        } catch {
            NSSound.beep()
            model.cancelEdit()
        }
    }
}

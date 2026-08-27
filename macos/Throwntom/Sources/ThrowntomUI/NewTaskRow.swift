import SwiftUI
import ThrowntomClient

/// Inline editor inserted above the active tasks while a new task is being typed.
struct NewTaskRow: View {
    /// What committing the editor's draft came to. Every outcome closes the row.
    enum DraftOutcome: Equatable {
        /// The command line the task window should send.
        case send(String)
        /// A blank draft: nothing to add.
        case nothing
        /// Text the daemon's task grammar will not take.
        case refused
    }

    let model: TaskWindowModel
    let onCommit: (String) -> Void
    /// The refusal alert. Injectable so tests can assert it fired without making a noise.
    var alert: () -> Void = { NSSound.beep() }

    @FocusState private var focused: Bool

    var body: some View {
        TextField("New task", text: Binding(
            get: { model.draft ?? "" },
            set: { model.draft = $0 }))
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { submit() }
            .onExitCommand { model.cancelEdit() }
    }

    /// Closes the row and says what its draft came to.
    func commit() -> DraftOutcome {
        do {
            if let line = try model.commitNewTask() { return .send(line) }
            return .nothing
        } catch {
            model.cancelEdit()
            return .refused
        }
    }

    /// Hands a usable line to the task window; a refusal beeps, since the row is already gone.
    func submit() {
        switch commit() {
        case let .send(line): onCommit(line)
        case .nothing: break
        case .refused: alert()
        }
    }
}

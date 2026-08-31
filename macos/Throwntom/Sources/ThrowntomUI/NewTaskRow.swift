import SwiftUI
import ThrowntomClient

/// Inline editor inserted above the active tasks while a new task is being typed.
struct NewTaskRow: View {

  // MARK: Internal

  /// What committing the editor's draft came to. Every outcome closes the row.
  enum DraftOutcome: Equatable {
    /// The command line the tasks panel should send.
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

  var body: some View {
    TextField("New task", text: $text)
      .textFieldStyle(.roundedBorder)
      .focused($focused)
      .onAppear {
        text = model.draft ?? ""
        focused = true
      }
      .onChange(of: text) { model.draft = text }
      .onSubmit { submit() }
      .onExitCommand { model.cancelEdit() }
  }

  /// Closes the row and says what its draft came to.
  func commit() -> DraftOutcome {
    do {
      if let line = try model.commitNewTask() {
        return .send(line)
      }
      return .nothing
    } catch {
      // The draft itself stays out of it: `ClientLog` records which grammar rule refused, and the
      // draft is the plainest user content in the app.
      ClientLog.failed("commit the new task", in: .tasks, error: error)
      model.cancelEdit()
      return .refused
    }
  }

  /// Hands a usable line to the tasks panel; a refusal beeps, since the row is already gone.
  func submit() {
    switch commit() {
    case .send(let line): onCommit(line)
    case .nothing: break
    case .refused: alert()
    }
  }

  // MARK: Private

  @FocusState private var focused: Bool
  @State private var text = ""

}

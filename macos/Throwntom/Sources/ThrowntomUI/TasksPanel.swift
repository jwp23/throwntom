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

  /// True when there is neither a task nor an open editor, so the list would render blank.
  var showsEmptyState: Bool {
    model.tasks.active.isEmpty && model.tasks.completed.isEmpty && !model.isEditing
  }

  /// The hint under the list, worded for the row the keys would act on: ⌘⇧F reads as its own undo
  /// on a task already focused.
  var hintLine: String {
    TaskHints.line(focused: model.isSelectedFocused)
  }

  /// The colour of a row's focus mark on this panel (see `PhaseScheme.panelTaskMark`).
  var markColor: HexColor {
    scheme.panelTaskMark
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Tasks").font(.caption).textCase(.uppercase)
      if showsEmptyState {
        Text(TaskHints.empty)
          .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
      } else {
        taskList
        ShortcutHint(hintLine)
      }
    }
    .padding(10)
    .foregroundStyle(scheme.panelText.color)
    .background(scheme.panel.color, in: RoundedRectangle(cornerRadius: 8))
  }

  // MARK: Private

  /// `NewTaskRow`'s scroll identity. Never a real task id — the daemon numbers tasks from 1.
  private static let newTaskRowID = -1

  @State private var showCompleted = false

  /// The id `taskList` should be scrolled to, so a row that just became first is never left
  /// clipped under the header. `List` keeps the scroll offset it had before a row was inserted
  /// above the old top row rather than resetting it, so without this the new top row opens
  /// partly hidden.
  private var topRowID: Int? {
    model.isEditing ? Self.newTaskRowID : model.tasks.active.first?.id
  }

  private var taskList: some View {
    ScrollViewReader { proxy in
      List(selection: $model.selectedID) {
        if model.isEditing {
          NewTaskRow(model: model) { line in DaemonDispatch.send(line, to: environment.client) }
            .id(Self.newTaskRowID)
        }
        ForEach(model.tasks.active) { task in
          TaskRow(task: task, focused: model.focusedIDs.contains(task.id), markColor: markColor)
            .tag(task.id)
            .contextMenu { TaskContextMenu(task: task, environment: environment) }
        }
        if !model.tasks.completed.isEmpty {
          DisclosureGroup(model.completedSectionTitle, isExpanded: $showCompleted) {
            ForEach(model.tasks.completed) { task in
              TaskRow(task: task, focused: false, markColor: markColor)
            }
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .frame(minHeight: 160, maxHeight: 280)
      .onChange(of: topRowID, initial: true) { _, id in
        if let id {
          proxy.scrollTo(id, anchor: .top)
        }
      }
    }
  }

}

import Foundation
import ThrowntomClient

/// What the task window shows for one snapshot of daemon and editor state. Deciding it here
/// keeps the placeholder, section and toolbar rules out of the SwiftUI body.
struct TaskWindowContent: Equatable {

  // MARK: Lifecycle

  @MainActor
  init(state: DaemonState?, connection: DaemonClient.Connection, model: TaskWindowModel, now: Date) {
    placeholder = ConnectionStatus.placeholderText(state: state, connection: connection, now: now)
    isEditing = model.isEditing
    active = model.tasks.active
    focusedIDs = model.focusedIDs
    completed = model.tasks.completed.isEmpty
      ? nil
      : CompletedSection(title: model.completedSectionTitle, tasks: model.tasks.completed)
    toolbarActions = state.map(TimerActions.available(for:)) ?? []
  }

  // MARK: Internal

  struct CompletedSection: Equatable {
    let title: String
    let tasks: [TaskItem]
  }

  /// Overlay text while the daemon has sent no state yet; nil once state has arrived.
  let placeholder: String?
  /// Whether the inline new-task row is open.
  let isEditing: Bool
  let active: [TaskItem]
  let focusedIDs: Set<Int>
  /// nil when nothing has been completed, so the disclosure group is left out entirely.
  let completed: CompletedSection?
  let toolbarActions: [TimerAction]

}

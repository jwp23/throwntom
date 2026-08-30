import Foundation
import ThrowntomClient

// MARK: - MainWindowContent

/// Everything the window shows for one snapshot of daemon, connection and panel state. Deciding it here
/// keeps the phase, countdown and chip rules out of the SwiftUI bodies and under unit test.
struct MainWindowContent: Equatable {

  // MARK: Lifecycle

  init(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    tasks: TaskList,
    error: String?,
    registrationFailed: Bool = false,
    panel: WindowPanel?,
    now: Date,
  ) {
    serviceAction = ServiceActions.startOrStop(connection: connection, registrationFailed: registrationFailed)
    scheme = Palette.scheme(for: state?.state)
    pose = MascotPose.pose(for: state?.state, pausedFrom: state?.pausedFrom ?? .idle)
    // A refused launch outranks a retained phase: the daemon that phase came from is gone, so
    // the title must say the launch failed rather than go on naming a phase nothing is running.
    title = registrationFailed
      ? ConnectionStatus.text(state: state, connection: connection, registrationFailed: true, now: now)
      : state.map(Self.phaseTitle)
        ?? ConnectionStatus.placeholderText(
          state: nil,
          connection: connection,
          registrationFailed: false,
          now: now,
        )
        ?? ""
    countdown = state.flatMap { Self.countdown(for: $0, now: now) }
    nextStage = state?.nextStage.map { "Next: \($0.summary)" }
    garden = state
      .map { TomatoGarden(completedToday: $0.completedToday, inBlock: $0.workSessionsInBlock, every: $0.longBreakEvery) }
    chips = state.map(TimerActions.available(for:)) ?? []
    primaryChip = [TimerAction.confirm, .start, .resume].first(where: chips.contains)
    focused = state.map { tasks.focused(ids: $0.focusedTaskIds) } ?? []
    self.error = error
    self.panel = panel
  }

  // MARK: Internal

  let scheme: PhaseScheme
  let pose: MascotPose
  let title: String
  let countdown: String?
  let nextStage: String?
  let garden: TomatoGarden?
  let chips: [TimerAction]
  let primaryChip: TimerAction?
  /// Start or Stop for the timer service itself, which is offered whatever the timer is doing.
  let serviceAction: ServiceAction
  let focused: [TaskItem]
  let error: String?
  let panel: WindowPanel?

  // MARK: Private

  /// The phase's own name, except while the user has ended the day: the daemon is idle then, and
  /// "Idle" would read as a timer waiting to be started rather than as a day that is over.
  private static func phaseTitle(for state: DaemonState) -> String {
    if state.state == .idle, state.dayEnded {
      "Done for today"
    } else {
      state.state.displayName
    }
  }

  private static func countdown(for state: DaemonState, now: Date) -> String? {
    switch state.state {
    case .work,
         .shortBreak,
         .longBreak:
      state.phaseEndAt.map { Countdown.formatRemaining($0.timeIntervalSince(now)) }
    case .paused:
      Countdown.formatRemaining(TimeInterval(state.pausedRemaining))
    case .idle,
         .awaitingConfirm:
      nil
    }
  }

}

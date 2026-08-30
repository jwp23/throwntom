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
    status: ServiceStatus,
    tasks: TaskList,
    error: String?,
    panel: WindowPanel?,
    now: Date,
  ) {
    serviceAction = ServiceActions.startOrStop(status: status)
    // An absent service outranks a retained phase: the daemon that phase came from is gone, so
    // nothing derived from it is true any more. The whole window drops to its disconnected
    // presentation — no phase colour, countdown, garden, focus list, panel, and above all no timer
    // chips, which would dispatch to a daemon already confirmed gone.
    //
    // Stopping here rather than clearing `DaemonClient.state` is deliberate. That state is the
    // client's, not this window's: `AppMenus` and `ShortcutSheet` build the Timer menu from it
    // and `MainWindow` syncs focus from it, so blanking it to dress one window would blank those
    // too — and a view reaching back to edit the model is the wrong layer either way. The same
    // goes for the panel: `WindowModel` keeps holding it, so it comes back with the daemon rather
    // than having to be reopened.
    //
    // Showing none of it costs nothing durable: the daemon owns the day's real position, saves
    // it to session.json and republishes it on the next connection (`internal/core/session.go`).
    //
    // A live connection outranks a stale refusal inside `ServiceStatus.of`, matching
    // `DaemonClient.unresolvedError`, so a note about launchd can never blank a running timer.
    let shown = status.offersDaemonCommands ? state : nil
    scheme = Palette.scheme(for: shown?.state)
    pose = MascotPose.pose(for: shown?.state, pausedFrom: shown?.pausedFrom ?? .idle)
    title = shown.map(Self.phaseTitle)
      ?? ConnectionStatus.text(state: nil, connection: connection, status: status, now: now)
    countdown = shown.flatMap { Self.countdown(for: $0, now: now) }
    nextStage = shown?.nextStage.map { "Next: \($0.summary)" }
    garden = shown
      .map { TomatoGarden(completedToday: $0.completedToday, inBlock: $0.workSessionsInBlock, every: $0.longBreakEvery) }
    chips = shown.map(TimerActions.available(for:)) ?? []
    primaryChip = [TimerAction.confirm, .start, .resume].first(where: chips.contains)
    focused = shown.map { tasks.focused(ids: $0.focusedTaskIds) } ?? []
    self.error = error
    notice = status.explanation
    // A panel left open when the service went down would show a stale list whose rows refuse, or
    // open onto nothing at all.
    self.panel = status.offersDaemonCommands ? panel : nil
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
  /// Why nothing is running, on the screens where the title alone leaves that unanswered. Kept
  /// apart from `error` because they are different things to read: one reports a fault, the other
  /// explains a window doing exactly what it was asked to.
  let notice: String?
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

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
    // A refused launch outranks a retained phase: the daemon that phase came from is gone, so
    // nothing derived from it is true any more. The whole window drops to its disconnected
    // presentation — no phase colour, countdown, garden, focus list, and above all no timer
    // chips, which would dispatch to a daemon already confirmed gone.
    //
    // Stopping here rather than clearing `DaemonClient.state` is deliberate. That state is the
    // client's, not this window's: `AppMenus` and `ShortcutSheet` build the Timer menu from it
    // and `MainWindow` syncs focus from it, so blanking it to dress one window would blank those
    // too — and a view reaching back to edit the model is the wrong layer either way.
    //
    // Showing none of it costs nothing durable: the daemon owns the day's real position, saves
    // it to session.json and republishes it on the next connection (`internal/core/session.go`).
    //
    // `connection != .connected` keeps this in step with `DaemonClient.unresolvedError`, which
    // lets a live connection outrank a refusal so a stale one can never be shown over a running
    // timer. The combination is unreachable today — `runStream` clears `registrationError`
    // before it reports `.connected` — but if it ever were, disagreeing would blank the window
    // and suppress the note explaining why, which is worse than either alone.
    let shown = registrationFailed && connection != .connected ? nil : state
    scheme = Palette.scheme(for: shown?.state)
    pose = MascotPose.pose(for: shown?.state, pausedFrom: shown?.pausedFrom ?? .idle)
    title = shown.map(Self.phaseTitle)
      ?? ConnectionStatus.text(state: nil, connection: connection, registrationFailed: registrationFailed, now: now)
    countdown = shown.flatMap { Self.countdown(for: $0, now: now) }
    nextStage = shown?.nextStage.map { "Next: \($0.summary)" }
    garden = shown
      .map { TomatoGarden(completedToday: $0.completedToday, inBlock: $0.workSessionsInBlock, every: $0.longBreakEvery) }
    snoozeNote = shown?.snoozeUntil.map { Self.snoozeNote(until: $0, now: now) }
    chips = shown.map(TimerActions.available(for:)) ?? []
    primaryChip = [TimerAction.confirm, .start, .resume].first(where: chips.contains)
    focused = shown.map { tasks.focused(ids: $0.focusedTaskIds) } ?? []
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
  /// How much of an active snooze is left, or nil when none is running. Snoozing withdraws the
  /// reminder banner, so this is the only thing on screen that says a reminder is still owed.
  let snoozeNote: String?
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

  /// Time left rather than the hour it ends, for the same reason the phase shows a countdown:
  /// "nine minutes" is the question being asked, and it needs no locale to read.
  private static func snoozeNote(until: Date, now: Date) -> String {
    "Snoozed · \(Countdown.formatRemaining(until.timeIntervalSince(now))) left"
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

import Foundation
import ThrowntomClient

// MARK: - MainWindowContent

/// Everything the window shows for one snapshot of daemon, connection and panel state. Deciding it here
/// keeps the phase, countdown and chip rules out of the SwiftUI bodies and under unit test.
struct MainWindowContent: Equatable {

  // MARK: Lifecycle

  /// `status` is derived from `connection` by the client, so in the app the two always agree and
  /// `connection` is read for one thing only: which of the three dialling phrasings to use when
  /// there is no phase to name. A test can pair them freely; nothing downstream trusts the pair.
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
    // A snooze is not a phase: the daemon publishes it beside the state (`internal/core/state.go`),
    // so while one runs `state` is still awaiting_confirm or idle. Ground, pose and title are asked
    // this question before they are asked the phase's, because the phase underneath an evening
    // snooze is the reminder the user has just quieted — and drawn from the phase alone the window
    // went on shouting it in alarm red with the mascot jumping. Snoozing also withdraws the banner
    // (`ReminderBanner`) and stops the window floating (`WindowElevation`), which leaves the window
    // itself as the only thing that can report a snooze at all.
    let snoozed = shown?.snoozeUntil != nil
    isSnoozed = snoozed
    // An outstanding morning nudge is not a phase either: the daemon publishes it as a flag beside
    // an idle state, so drawn from the phase alone the window said `Idle` — indistinguishable from
    // a timer nobody is waiting on. The nudge only rings for as long as `repeat_limit_secs`, and a
    // user who reached their desk after that had a notification long since scrolled away and a
    // window that admitted to nothing. It wears the confirm screen because it asks the same
    // question with the same urgency; only the title differs, because the verb does — this one is
    // answered by Start, not Confirm.
    let nudging = Self.isMorningNudge(shown)
    scheme = snoozed ? Palette.snoozed : Palette.scheme(for: nudging ? .awaitingConfirm : shown?.state)
    pose =
      if snoozed {
        .asleep
      } else if nudging {
        .awaitingConfirm
      } else {
        MascotPose.pose(for: shown?.state, pausedFrom: shown?.pausedFrom ?? .idle)
      }
    // A retained phase is still counting (ADR-008), so the window goes on naming it and keeps its
    // ground and its verbs — but it must not read as a live connection. Unmarked, a client that has
    // lost the daemon draws a window byte-for-byte identical to the connected one, and the only way
    // to find out is to wait for the retry budget to run out (throwntom-7rb). The mark is on the
    // title alone: the countdown and the ground are as true as they were.
    //
    // "reconnecting" rather than "connecting" is exact here, not a guess: `state` is only ever set
    // from a decoded frame and only ever cleared by `stopService()`, which clears `hasConnected`
    // with it, so a phase in hand means this client has reached a daemon since the last stop.
    let title = shown.map { Self.phaseTitle(for: $0) + (status == .reaching ? " (reconnecting)" : "") }
      ?? ConnectionStatus.text(connection: connection, status: status)
    self.title = title
    countdown = shown.flatMap { Self.countdown(for: $0, now: now) }
    let nextStage = shown?.nextStage.map { "Next: \($0.summary)" }
    self.nextStage = nextStage
    // The headline's three lines are one thing to read, not three (throwntom-jnv). The countdown
    // is left out because it is the element's *value* rather than part of its name: a label that
    // carried it would be a different label every second, and VoiceOver reads a changed label as a
    // new element rather than as the same one counting down.
    spokenHeadline = nextStage.map { "\(title). \($0)" } ?? title
    garden = shown
      .map { TomatoGarden(completedToday: $0.completedToday, inBlock: $0.workSessionsInBlock, every: $0.longBreakEvery) }
    isMeeting = shown?.state == .meeting
    chips = shown.map(TimerActions.available(for:)) ?? []
    startTitle = TimerActions.startTitle(for: shown)
    primaryChip = [TimerAction.confirm, .start, .resume].first(where: chips.contains)
    focused = shown.map { tasks.focused(ids: $0.focusedTaskIds) } ?? []
    self.error = error
    notice = status.explanation
    // A panel left open when the service went down would show a stale list whose rows refuse, or
    // open onto nothing at all.
    self.panel = status.offersDaemonCommands ? panel : nil
  }

  // MARK: Internal

  /// What the window calls an unanswered morning nudge. It names what is owed rather than the
  /// phase underneath, which is idle, and it echoes the notification's own words so the two read
  /// as one reminder rather than as two things asking for attention.
  static let morningNudgeTitle = "Ready to start?"

  let scheme: PhaseScheme
  let pose: MascotPose
  let title: String
  let countdown: String?
  let nextStage: String?
  /// The headline as one thing to read out: the phase and the stage after it, without the
  /// countdown, which is carried as the element's value instead (`TimerHeader`).
  let spokenHeadline: String
  let garden: TomatoGarden?
  /// Whether a snooze is running. It is what the ground, the pose and the title above are keyed
  /// on, and what turns the snooze chip into the way out of one, so all four read one answer.
  let isSnoozed: Bool
  /// Whether a meeting is running, which is what turns the meeting chip into the way out of one.
  /// Read from the phase the window is showing rather than from the daemon state again, so the
  /// chip's face can never disagree with the ground and title around it — a client that has lost
  /// the daemon draws no phase, and must not go on offering to end a meeting it cannot end.
  let isMeeting: Bool
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

  /// What a verb's control says on this screen. Everything but Start says what it always says;
  /// Start names the phase an idle start would enter, which only the daemon knows.
  func title(for action: TimerAction) -> String {
    action == .start ? startTitle : action.title
  }

  // MARK: Private

  /// Resolved once at build time so the chip row cannot drift from the Timer menu, which asks
  /// `TimerActions.startTitle(for:)` the same question off the same gated state. The cheat sheet
  /// asks it with no state at all and so always says the bare verb, deliberately: it is a
  /// reference to what is bound, not a report of what is live.
  private let startTitle: String

  /// The phase's own name, except for the three situations the phase does not describe: a snooze,
  /// which the daemon reports beside the state and which leaves that state naming the reminder it
  /// silenced; a day the user has ended, where the daemon is idle and "Idle" would read as a
  /// timer waiting to be started rather than as a day that is over; and an outstanding morning
  /// nudge, where the daemon is idle and the user is the one being waited on.
  private static func phaseTitle(for state: DaemonState) -> String {
    if state.snoozeUntil != nil {
      "Snoozed"
    } else if state.state == .idle, state.dayEnded {
      "Done for today"
    } else if isMorningNudge(state) {
      morningNudgeTitle
    } else {
      state.state.displayName
    }
  }

  /// Whether an unanswered morning nudge is what this window is showing. One definition, because
  /// the title, the ground and the pose have to agree: a window that named the nudge on an idle
  /// ground, or shouted in alarm red under the word `Idle`, would be worse than either alone.
  ///
  /// A snooze outranks it for the reason the snoozed presentation exists at all — the reminder a
  /// user has just quieted must not go on shouting — and an ended day outranks it because
  /// `skipToday` retires the reminder along with the day (`internal/core/outstanding.go`), so the
  /// two together are a contradiction, and "Done for today" is the half of it that is true.
  private static func isMorningNudge(_ state: DaemonState?) -> Bool {
    guard let state else { return false }
    return state.snoozeUntil == nil && !state.dayEnded && state.state == .idle && state.morningPending
  }

  /// Both of what a snooze owes the reader, in the slot the phase countdown would have used. The
  /// hour is what gets checked against a calendar — whether the thing in hand fits before the
  /// reminder comes back — and the minutes left are what gets checked against patience. Neither
  /// answers the other's question, so the header carries the two.
  private static func snoozeReturn(until: Date, now: Date) -> String {
    "Back at \(Countdown.formatTimeOfDay(until)) · \(Countdown.formatRemaining(until.timeIntervalSince(now)))"
  }

  private static func countdown(for state: DaemonState, now: Date) -> String? {
    if let until = state.snoozeUntil {
      return snoozeReturn(until: until, now: now)
    }
    return switch state.state {
    case .work,
         .shortBreak,
         .longBreak,
         .lunch,
         .meeting:
      state.phaseEndAt.map { Countdown.formatRemaining($0.timeIntervalSince(now)) }
    case .paused:
      Countdown.formatRemaining(TimeInterval(state.pausedRemaining))
    case .idle,
         .awaitingConfirm:
      nil
    }
  }

}

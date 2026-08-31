public enum TimerActions {
  public static let defaultSnoozeMinutes = 10

  /// Verbs to offer in this state, in display order. A display list rather than a transcript of
  /// what `internal/core/commands.go` accepts: the daemon also accepts `start` at awaiting-confirm,
  /// where it does exactly what `confirm` does, and offering both would put two chips on one screen
  /// for one outcome. Every verb listed here is one the daemon accepts; the converse is not claimed.
  ///
  /// Ending the day comes last in every state rather than only while idle: `handleSkipToday` has
  /// no state guard, and a user who is finished mid-pomodoro needs to be able to say so without
  /// first pausing or waiting out the phase.
  public static func available(for state: DaemonState) -> [TimerAction] {
    switch state.state {
    case .idle:
      // Not once the day is already ended: that screen is what the verb produces, and a chip
      // that re-ends an ended day does nothing.
      if state.dayEnded {
        [.start, .newCycle]
      } else if state.morningPending {
        [.start, .newCycle, .snooze, .skipToday]
      } else {
        [.start, .newCycle, .skipToday]
      }

    // Skip ends the running phase, so it is on offer only while one is running.
    case .work,
         .shortBreak,
         .longBreak:
      [.pause, .skip, .skipToday]

    case .paused:
      [.resume, .skipToday]

    case .awaitingConfirm:
      [.confirm, .snooze, .newCycle, .skipToday]
    }
  }

  /// What the Start control says: the phase an idle start would enter, when the daemon has said
  /// which. Only an idle timer owes a phase, so every other state — and a client with no state at
  /// all — falls back to the plain verb rather than inventing one.
  ///
  /// Naming the phase is the point: stop is a suspend, so Start over an "Idle" title can begin the
  /// short break the user earned rather than the pomodoro they expected (throwntom-46y).
  public static func startTitle(for state: DaemonState?) -> String {
    guard let owed = state?.owedStage else { return TimerAction.start.title }
    return "\(TimerAction.start.title) \(owed.state.displayName)"
  }

  /// The single play/pause control: resuming is only on offer while the timer is paused.
  public static func pauseOrResume(for phase: DaemonState.Phase?) -> TimerAction {
    if phase == .paused {
      .resume
    } else {
      .pause
    }
  }
}

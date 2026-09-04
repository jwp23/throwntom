import Foundation
import ThrowntomClient

/// What a change in the daemon's state means for the Dock. Two things ask for the user's eye: a
/// reminder waiting to be answered, and a pause the daemon has been keeping the clock on long
/// enough to call forgotten (`paused_too_long_minutes`). Neither is a decision made here — the
/// daemon owns the timing (ADR-003) and this owns only when the app starts and stops asking.
///
/// Deciding from two states rather than the latest one is what keeps a wait that lasts many frames
/// to one request. `.criticalRequest` bounces until the app is activated or the request is
/// cancelled, so one is the right number: a second while the first is outstanding would leak its
/// identifier and leave nothing able to call the bounce off.
enum DockAttention: Equatable {
  case request
  case cancel
  /// Either nothing is being asked for, or what is being asked for has not changed.
  case unchanged

  // MARK: Internal

  static func decide(from previous: DaemonState?, to current: DaemonState) -> DockAttention {
    // The reminder's own rule is finer than "is one outstanding": the morning nudge giving way to
    // a cycle reminder is a new question, and asks again.
    if ReminderBanner.wantsAttention(from: previous, to: current) {
      return .request
    }
    if current.pausedTooLong, current.bounceDockWhenPaused, previous?.pausedTooLong != true {
      return .request
    }
    // The request outstanding is still wanted, whether it was made for this reason or not: at most
    // one of the two can be true at a time, since a pause is not a phase awaiting an answer.
    if wanted(current) {
      return .unchanged
    }
    return wanted(previous) ? .cancel : .unchanged
  }

  // MARK: Private

  /// Whether the daemon wanted the user's eye in this state. A state the app cannot read is not an
  /// answer to anything, so the caller keeps the last one it could read rather than passing nil.
  /// `bounceDockWhenPaused` is read from the same state as `pausedTooLong`, so a live reload that
  /// turns it off is read from `current` here and, through `wanted(previous)` on the request that
  /// state made when it was `current`, cancels a bounce already in progress.
  private static func wanted(_ state: DaemonState?) -> Bool {
    guard let state else { return false }
    return ReminderBanner.isWaiting(state) || (state.pausedTooLong && state.bounceDockWhenPaused)
  }
}

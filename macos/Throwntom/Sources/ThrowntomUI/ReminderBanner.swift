import Foundation
import ThrowntomClient
import UserNotifications

// MARK: - ReminderPresenter

/// The notification-centre operations a reminder needs, so what the app shows can be worked out
/// without the user's real notification centre, which no test process may reach.
protocol ReminderPresenter {
  /// Attaches each reminder's buttons to its category. Without it macOS shows the banner
  /// with no buttons on it and the reminder cannot be answered.
  func registerReminderButtons()
  func postReminder(title: String, body: String) async throws
  func postMorningReminder(title: String, body: String) async throws
  func withdrawReminder()
  /// Draws the eye to the app without taking focus: on macOS, the Dock icon bounces.
  func requestAttention()
  /// Stops the Dock bouncing. Activating the app cancels the request too, but the daemon can stop
  /// wanting the user's eye without them ever coming to the app — a reminder answered from the
  /// terminal, a pause resumed there — and the bounce must not outlive the reason for it.
  func cancelAttention()
  /// Raises the window so it can be read, without activating the app and without taking key
  /// focus. This is a reply to something the user just pressed — what a reminder button does when
  /// there is no timer service to answer it, so the window can say why instead of the button
  /// vanishing in silence — but a nudge must never take the keyboard from whatever they are
  /// typing in (throwntom-lbw). The name carries the constraint because nothing else can: an
  /// implementation that reached for `activate` or `makeKeyAndOrderFront` would contradict it.
  func showWindowWithoutFocus()
  /// Sounds one ring of the reminder. The banner carries no sound of its own (ADR-009), so this
  /// is the whole audio path — ring one included, and every repeat the daemon no longer plays.
  func chime()
}

// MARK: - ReminderBanner

/// What a change in the daemon's state means for the reminder banner. Deciding it from the two
/// states rather than from the latest one is what keeps a wait that lasts many frames to one banner.
enum ReminderBanner: Equatable {
  case post(title: String, body: String)
  /// The morning nudge: idle with nothing running yet, its own title/body and its own actions.
  case postMorning(title: String, body: String)
  case withdraw
  /// The banner already matches the daemon and is left as it is.
  case unchanged

  // MARK: Internal

  static let title = "Throwntom"

  /// The body when the daemon names no stage to move on to, so the banner never shows a blank line.
  static let unnamedStage = "Ready for the next stage."

  static let morningBody = "Ready to start your day?"

  /// Both states are the daemon's own account of itself. A daemon that cannot be read gives no
  /// account at all, which is not a change to decide from; the caller keeps the banner instead.
  static func decide(
    from previous: DaemonState?,
    to current: DaemonState,
    authorization: ReminderAuthorization,
  ) -> ReminderBanner {
    let previousWaiting = waitingKind(previous)
    guard authorization.willDeliver else {
      return previousWaiting == nil ? .unchanged : .withdraw
    }
    let waiting = waitingKind(current)
    guard waiting != previousWaiting else { return .unchanged }
    guard let waiting else { return .withdraw }
    switch waiting {
    case .cycle:
      return .post(title: title, body: current.nextStage?.summary ?? unnamedStage)
    case .morning:
      return .postMorning(title: title, body: morningBody)
    }
  }

  /// Whether the user owes an answer to either reminder. The same question the banner decides
  /// from, for callers that need only the yes or no — so what counts as an outstanding reminder
  /// is settled in one place.
  static func isWaiting(_ state: DaemonState?) -> Bool {
    waitingKind(state) != nil
  }

  /// Whether the Dock should bounce for this change, independent of whether a notification can
  /// be posted: a denied notification is not a reason to withhold the bounce.
  static func wantsAttention(from previous: DaemonState?, to current: DaemonState) -> Bool {
    let waiting = waitingKind(current)
    return waiting != nil && waitingKind(previous) != waiting
  }

  // MARK: Private

  /// The two reminders the daemon ever raises. At most one is outstanding at a time: the cycle
  /// reminder only at `awaitingConfirm`, the morning nudge only at `idle`. See ADR-004.
  private enum Waiting: Equatable {
    case cycle
    case morning
  }

  /// Which reminder, if any, the daemon is asking the user about right now. A snooze does not
  /// answer the reminder — it stays outstanding, only suppressed until its deadline (ADR-004) —
  /// but there is nothing to put a banner in front of the user about while it is quiet.
  private static func waitingKind(_ state: DaemonState?) -> Waiting? {
    guard let state, state.snoozeUntil == nil else { return nil }
    if state.state == .awaitingConfirm {
      return .cycle
    }
    if state.state == .idle, state.morningPending {
      return .morning
    }
    return nil
  }
}

import Foundation

/// How long to wait before the next dial at the daemon, and when to ask launchd to start it.
///
/// Registering the agent rewinds the delay to the short end, once per outage: registration is
/// the thing that ends the outage, so the dial that checks whether it worked should come soon
/// after rather than at the escalated end. Without the rewind the client pays for its own fix
/// in multi-second steps, which is how a first launch took ~26 s to show a timer.
struct ReconnectBackoff {

  // MARK: Lifecycle

  init(delays: [Duration], registerEvery: Int) {
    precondition(!delays.isEmpty, "backoff needs at least one delay")
    precondition(registerEvery > 0, "the agent has to be registered at some point")
    self.delays = delays
    self.registerEvery = registerEvery
  }

  // MARK: Internal

  /// Consecutive failed dials since the last frame arrived.
  private(set) var failures = 0

  /// Whether launchd has already been asked to start the daemon during this outage.
  private(set) var hasAskedLaunchdToStart = false

  /// Whether this failure is the one that asks launchd to start the daemon.
  var shouldRegisterAgent: Bool {
    failures > 0 && failures % registerEvery == 0
  }

  /// How long to wait before the next dial.
  var delay: Duration {
    delays[min(delayIndex, delays.count - 1)]
  }

  mutating func recordFailure() {
    failures += 1
    if failures > 1 {
      delayIndex += 1
    }
  }

  /// Rewinds the delay after the first registration of an outage. Later registrations leave the
  /// escalation alone, so an outage registration cannot fix keeps backing off instead of
  /// hammering launchd every few hundred milliseconds.
  mutating func agentRegistered() {
    guard !hasAskedLaunchdToStart else { return }
    hasAskedLaunchdToStart = true
    delayIndex = 0
  }

  /// Called when the daemon answers: the next outage starts from scratch.
  mutating func reset() {
    failures = 0
    delayIndex = 0
    hasAskedLaunchdToStart = false
  }

  // MARK: Private

  private let delays: [Duration]
  private let registerEvery: Int
  private var delayIndex = 0

}

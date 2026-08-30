import Foundation

/// How long to wait before the next dial at the daemon, and when to ask launchd to start it.
///
/// Registering the agent rewinds the delay to the short end, once per outage: registration is
/// the thing that ends the outage, so the dial that checks whether it worked should come soon
/// after rather than at the escalated end. Without the rewind the client pays for its own fix
/// in multi-second steps, which is how a first launch took ~26 s to show a timer.
///
/// The once is load-bearing in its own right, not just for the rewind: see
/// `registerAgentIfDue(_:)`.
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

  /// Asks launchd to start the daemon, through `register`, on the failure that calls for it, and
  /// rewinds the delay when launchd accepts. `register` reports whether the ask was accepted;
  /// a refusal fixed nothing, so the outage keeps escalating and a later failure asks again.
  ///
  /// At most one accepted registration per outage. Registering is unregister-then-register, so a
  /// second one boots out the daemon the first one started, and launchd's 10 s minimum runtime
  /// then throttles the respawn - the client's recovery causing the outage it recovers from.
  /// After an accepted ask, KeepAlive is what keeps trying; asking again can only interrupt it.
  ///
  /// The decision and the bookkeeping are one call because they were separate: a caller that
  /// read the decision and forgot the bookkeeping silently lost the rewind, with no test failing
  /// except under wall-clock conditions.
  ///
  /// `register` must not touch this backoff: the call holds exclusive access for its duration,
  /// so reading `delay` or `failures` from inside it traps on overlapping access.
  mutating func registerAgentIfDue(_ register: () -> Bool) {
    guard !hasAskedLaunchdToStart, failures > 0, failures % registerEvery == 0 else { return }
    guard register() else { return }
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

  /// Whether launchd has already accepted a request to start the daemon during this outage.
  private var hasAskedLaunchdToStart = false

}

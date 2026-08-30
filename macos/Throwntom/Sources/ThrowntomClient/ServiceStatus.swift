import Foundation

/// Whether the timer service is there, and when it is not, why not. The three absent readings are
/// deliberately separate values: a service the user switched off, a service launchd would not
/// launch, and a service still being dialled are three different situations, and the reader's next
/// move differs in each. A window that renders any two of them alike makes them guess which.
///
/// Derived from the client's observable properties rather than stored, so there is one answer for
/// the window, the menu bar, the chip rows and the panels instead of four that can drift apart.
public enum ServiceStatus: Hashable, Sendable {
  /// A daemon is connected and publishing state.
  case running
  /// Dialling, or waiting on a launch that has not failed yet. Transient, and not a failure: the
  /// phase the client already holds is still counting, so the window keeps showing it.
  case reaching
  /// The user pressed Stop Timer Service. It stays stopped, across relaunches, until they press
  /// Start.
  case stopped
  /// launchd refused to start the daemon.
  case launchRefused
  /// launchd accepted the request to start the daemon and no daemon ever arrived.
  case notAnswering

  // MARK: Public

  /// Whether an affordance that sends the daemon a command should be offered at all. Everything
  /// that reaches the daemon — the timer chips, the Timer menu and its key equivalents, the task
  /// verbs, the two panels and the chips that open them — asks this one question, so no surface
  /// can be fixed while another goes on dispatching into nothing.
  ///
  /// Dialling counts as available: the daemon is expected back within a backoff step, the retained
  /// phase is still true, and withdrawing every verb for a blink of the socket would be worse than
  /// the refusal a command would meet.
  /// Switched rather than compared, because this one property gates every affordance in the app
  /// that reaches the daemon: a case added later has to be decided here, not fall through.
  public var offersDaemonCommands: Bool {
    switch self {
    case .running,
         .reaching: true
    case .stopped,
         .launchRefused,
         .notAnswering: false
    }
  }

  /// The sentence under the status line, on the screens where the line alone leaves the reader
  /// asking why nothing is happening. Nil where there is nothing to add: a running or dialling
  /// service explains itself, and a refused launch already has the client's `registrationError`,
  /// written at the moment launchd said no.
  public var explanation: String? {
    switch self {
    case .stopped:
      "You stopped the timer service. It stays stopped until you press \(ServiceAction.start.title)."

    case .notAnswering:
      "launchd accepted the request to start the timer service, but it has not answered. "
        + "It may need approval in Login Items."

    case .running,
         .reaching,
         .launchRefused:
      nil
    }
  }

  /// Reads the client's connection and launch bookkeeping as one of the five situations.
  ///
  /// The order is the precedence. A stop is the user's own decision and outranks whatever the
  /// dialling machinery was reporting when they made it. A live connection outranks both launch
  /// readings, matching `DaemonClient.unresolvedError`, so a stale refusal can never be shown over
  /// a running timer. A refusal outranks a stall because launchd saying no is the more specific
  /// answer than nothing having arrived.
  public static func of(
    connection: DaemonClient.Connection,
    registrationFailed: Bool,
    startStalled: Bool,
  ) -> ServiceStatus {
    if connection == .stopped {
      return .stopped
    }
    if connection == .connected {
      return .running
    }
    if registrationFailed {
      return .launchRefused
    }
    return startStalled ? .notAnswering : .reaching
  }
}

import Foundation

/// The status text shown for the daemon connection: the phrase for every service situation, used
/// wherever the window has no phase of its own to name. View-independent so it can be unit tested.
public enum ConnectionStatus {

  // MARK: Public

  /// `status` outranks the dialling states, which is why it is asked first. The reconnect loop
  /// keeps retrying after launchd has refused and after an accepted start has gone silent, so the
  /// connection alone still reads as "starting" long after the start has stopped being in
  /// progress; saying so would be wrong rather than merely redundant.
  ///
  /// Each absent situation gets its own line, because the line is what a reader tells them apart
  /// by: a service they switched off, a launch that failed, and a launch that was accepted and
  /// brought nothing are three different things to do next. `connection` is still read for the
  /// transient case, where the wording turns on whether this is a first dial or a lost one.
  public static func text(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    status: ServiceStatus,
    now: Date,
  ) -> String {
    if let state, status == .running {
      return Countdown.tickedStatusLine(state, now: now)
    }
    switch status {
    case .stopped: return "Timer service stopped"

    case .launchRefused: return "Timer service can’t launch"

    case .notAnswering: return "Timer service isn’t answering"

    case .running: return "Throwntom"

    case .reaching: return reachingText(state: state, connection: connection, now: now)
    }
  }

  // MARK: Private

  /// A dial in progress, worded for whether the client has a phase in hand: with one, that phase
  /// is still counting and the line goes on naming it. A start launchd has just been asked for is
  /// the exception — nothing is counting yet, so it names the start instead.
  private static func reachingText(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String {
    switch connection {
    case .startingDaemon:
      "Starting timer…"

    case .reconnecting:
      state.map { Countdown.tickedStatusLine($0, now: now) + " (reconnecting)" } ?? "Reconnecting…"

    default:
      state.map { Countdown.tickedStatusLine($0, now: now) + " (reconnecting)" } ?? "Connecting…"
    }
  }

}

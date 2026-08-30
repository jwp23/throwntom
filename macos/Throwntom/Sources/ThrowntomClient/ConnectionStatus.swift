import Foundation

/// The status text for a window with no phase of its own to name: the phrase for every service
/// situation where nothing is counting. A window that still holds a phase names that phase instead
/// and marks it itself (`MainWindowContent`), so no state is passed here and none is read.
/// View-independent so it can be unit tested.
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
    connection: DaemonClient.Connection,
    status: ServiceStatus,
  ) -> String {
    switch status {
    case .stopped: "Timer service stopped"

    case .launchRefused: "Timer service can’t launch"

    case .notAnswering: "Timer service isn’t answering"

    case .running: "Throwntom"

    case .reaching: reachingText(connection: connection)
    }
  }

  // MARK: Private

  /// A dial in progress with nothing counting behind it, worded for what is actually happening:
  /// a launch already asked of launchd, a connection lost and being chased, or a first dial. The
  /// three are different waits and the reader is owed which one they are in — a first connection
  /// is not "re"-anything (throwntom-ibf).
  private static func reachingText(connection: DaemonClient.Connection) -> String {
    switch connection {
    case .startingDaemon:
      "Starting timer…"

    case .reconnecting:
      "Reconnecting…"

    case .connecting:
      "Connecting…"

    // Neither reaches this: `ServiceStatus.of` resolves them to `.running` and `.stopped`, which
    // the caller answers above. Spelled out rather than left to a `default` so that a new
    // connection case has to be worded here instead of silently reading as a first dial.
    case .connected,
         .stopped:
      "Connecting…"
    }
  }

}

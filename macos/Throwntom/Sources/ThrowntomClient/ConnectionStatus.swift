import Foundation

/// The status text shown for the daemon connection: `text` is the phrase for every connection
/// state, `placeholderText` is the window's disconnected placeholder. View-independent so it
/// can be unit tested.
public enum ConnectionStatus {
  /// `registrationFailed` outranks every dialling state. The reconnect loop keeps retrying after
  /// launchd has refused, so the connection alone still reads as "starting" long after the start
  /// has definitively failed; saying so would be wrong rather than merely redundant. The note
  /// beside this line names launchd and points at Start Timer Service.
  public static func text(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    registrationFailed: Bool = false,
    now: Date,
  ) -> String {
    if let state, connection == .connected {
      return Countdown.tickedStatusLine(state, now: now)
    }
    if registrationFailed, connection != .stopped {
      return "Timer service can’t launch"
    }
    switch connection {
    case .stopped: return "Timer service stopped"

    case .startingDaemon: return "Starting timer…"

    case .connecting:
      return if let state {
        Countdown.tickedStatusLine(state, now: now) + " (reconnecting)"
      } else {
        "Connecting…"
      }

    case .reconnecting:
      return if let state {
        Countdown.tickedStatusLine(state, now: now) + " (reconnecting)"
      } else {
        "Reconnecting…"
      }

    case .connected: return "Throwntom"
    }
  }

  /// The text for the window's disconnected placeholder, or nil once daemon state has
  /// arrived and there is nothing to overlay.
  public static func placeholderText(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    registrationFailed: Bool = false,
    now: Date,
  ) -> String? {
    guard state == nil else { return nil }
    return text(state: state, connection: connection, registrationFailed: registrationFailed, now: now)
  }
}

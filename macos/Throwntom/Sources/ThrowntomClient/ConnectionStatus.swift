import Foundation

/// The status text shown for the daemon connection: `text` is the phrase for every connection
/// state, `placeholderText` is the window's disconnected placeholder. View-independent so it
/// can be unit tested.
public enum ConnectionStatus {
  public static func text(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String {
    if let state, connection == .connected {
      return Countdown.tickedStatusLine(state, now: now)
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
  public static func placeholderText(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String? {
    guard state == nil else { return nil }
    return text(state: state, connection: connection, now: now)
  }
}

import Foundation

/// The status text shown for the daemon connection, shared by the menu bar title and the
/// task window's disconnected placeholder. View-independent so it can be unit tested.
public enum ConnectionStatus {
    public static func text(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String {
        if let state, connection == .connected {
            return Countdown.tickedStatusLine(state, now: now)
        }
        switch connection {
        case .startingDaemon: return "Starting timer…"
        case .connecting, .reconnecting: return state.map { Countdown.tickedStatusLine($0, now: now) + " (reconnecting)" } ?? "Throwntom…"
        case .connected: return "Throwntom"
        }
    }
}

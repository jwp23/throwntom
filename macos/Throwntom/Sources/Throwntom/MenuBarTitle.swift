import Foundation
import ThrowntomClient

enum MenuBarTitle {
    static func text(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String {
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

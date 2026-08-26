import Foundation
import ThrowntomClient

enum MenuBarTitle {
    static func text(state: DaemonState?, connection: DaemonClient.Connection, now: Date) -> String {
        ConnectionStatus.text(state: state, connection: connection, now: now)
    }
}

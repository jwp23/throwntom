import Foundation
import ThrowntomClient

/// Everything the scenes read, wired together once at launch. Kept out of `ThrowntomApp` so the
/// wiring can be built and started without the SwiftUI app lifecycle.
@MainActor
final class AppEnvironment {
    let client: DaemonClient
    let ticker: Ticker
    let registrar: SMAppServiceRegistrar
    let model = TaskWindowModel()

    init(transport: DaemonTransport, ticker: Ticker? = nil) {
        let registrar = SMAppServiceRegistrar()
        self.registrar = registrar
        self.ticker = ticker ?? Ticker()
        client = DaemonClient(transport: transport, registrar: registrar)
    }

    /// What the app launches with: the daemon's Unix socket at its well-known path.
    static func live() -> AppEnvironment {
        AppEnvironment(transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath))
    }

    /// Starts the event stream and the countdown clock.
    func start() {
        client.start()
        ticker.start()
    }
}

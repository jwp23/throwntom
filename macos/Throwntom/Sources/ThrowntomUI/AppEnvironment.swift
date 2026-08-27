import Foundation
import ThrowntomClient

/// Everything the scenes read, wired together once at launch. Kept out of `ThrowntomApp` so the
/// wiring can be built and started without the SwiftUI app lifecycle.
@MainActor
final class AppEnvironment {
    let client: DaemonClient
    let ticker: Ticker
    let registrar: SMAppServiceRegistrar
    let responder: ReminderResponder
    let model = TaskWindowModel()

    init(
        transport: DaemonTransport,
        ticker: Ticker? = nil,
        authorizer: NotificationAuthorizer = SystemNotificationAuthorizer()
    ) {
        let registrar = SMAppServiceRegistrar()
        let client = DaemonClient(transport: transport, registrar: registrar)
        self.registrar = registrar
        self.ticker = ticker ?? Ticker()
        self.client = client
        responder = ReminderResponder(client: client, authorizer: authorizer)
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

    /// Claims the notification delegate, so a reminder answered while the menu bar app was not
    /// running still reaches the daemon. Kept apart from `start()` because it reaches for
    /// `UNUserNotificationCenter.current()`, which no process without an app bundle may do.
    func startReminderResponder() {
        responder.start()
    }
}

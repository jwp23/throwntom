import Foundation
import ThrowntomClient

/// Everything the scenes read, wired together once at launch. Kept out of `ThrowntomApp` so the
/// wiring can be built and started without the SwiftUI app lifecycle.
@MainActor
final class AppEnvironment {

  // MARK: Lifecycle

  init(
    transport: DaemonTransport,
    ticker: Ticker? = nil,
    authorizer: NotificationAuthorizer = SystemNotificationAuthorizer(),
    presenter: ReminderPresenter = SystemReminderPresenter(),
  ) {
    let registrar = SMAppServiceRegistrar()
    let client = DaemonClient(transport: transport, registrar: registrar)
    self.registrar = registrar
    self.ticker = ticker ?? Ticker()
    self.client = client
    responder = ReminderResponder(client: client, authorizer: authorizer, presenter: presenter)
  }

  // MARK: Internal

  let client: DaemonClient
  let ticker: Ticker
  let registrar: SMAppServiceRegistrar
  let responder: ReminderResponder
  let model = TaskWindowModel()
  let windowModel = WindowModel()

  /// What the app launches with: the daemon's Unix socket at its well-known path.
  static func live() -> AppEnvironment {
    AppEnvironment(transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath))
  }

  /// Starts the event stream and the countdown clock.
  func start() {
    client.start()
    ticker.start()
  }

  /// Claims the notification delegate and begins raising the reminder banner. Kept apart from
  /// `start()` because it reaches for `UNUserNotificationCenter.current()`, which no process
  /// without an app bundle may do.
  func startReminderResponder() {
    responder.start()
  }

}

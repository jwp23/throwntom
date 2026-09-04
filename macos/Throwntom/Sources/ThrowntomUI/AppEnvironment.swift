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
    intents: ServiceIntentStore = MemoryServiceIntentStore(),
    speaker: SpeechAnnouncer = SystemSpeechAnnouncer(),
  ) {
    let registrar = SMAppServiceRegistrar()
    let client = DaemonClient(transport: transport, registrar: registrar, intents: intents)
    self.registrar = registrar
    self.ticker = ticker ?? Ticker()
    self.client = client
    responder = ReminderResponder(client: client, authorizer: authorizer, presenter: presenter)
    announcements = AnnouncementResponder(client: client, speaker: speaker)
  }

  // MARK: Internal

  let client: DaemonClient
  let ticker: Ticker
  let registrar: SMAppServiceRegistrar
  let responder: ReminderResponder
  /// What tells assistive technology the timer service went down or came back. Held here rather
  /// than by the window so it follows the client for as long as the app runs.
  let announcements: AnnouncementResponder
  let model = TaskWindowModel()
  let windowModel = WindowModel()

  /// Whether a surface in front of the timer has Return: the inline new-task row, the custom-snooze
  /// duration field, or the cheat sheet, whose Done button is the default action. Confirm's key
  /// equivalent is offered to a main menu before whatever has focus ever sees it, so the surfaces
  /// have to be named for it to be handed back (`MenuModel.timer`).
  var returnIsTaken: Bool {
    returnIsTakenInTheWindow || windowModel.showsShortcuts
  }

  /// The same question with the cheat sheet left out of it, which is how the sheet asks it: the
  /// sheet is itself the surface in front for as long as anyone is reading it, and the reader is
  /// about to close it, so a Confirm withheld on the sheet's own account would be dim in the only
  /// place its row is ever seen. What the reader is going back to is a window that may still have
  /// a field open in it, and that much the sheet must still report.
  var returnIsTakenInTheWindow: Bool {
    model.isEditing || windowModel.isEnteringSnooze
  }

  /// What the app launches with: the daemon's Unix socket at its well-known path, and the one
  /// intent store that outlives the process — this is the single place persistence is asked for,
  /// so nothing built for a test can write a stopped service into the user's defaults.
  static func live() -> AppEnvironment {
    AppEnvironment(
      transport: UnixSocketTransport(socketPath: DaemonPaths.socketPath),
      intents: UserDefaultsServiceIntentStore(),
    )
  }

  /// Starts the event stream, the countdown clock, and the spoken account of the service.
  ///
  /// Announcing belongs here rather than with the reminder responder below: it reaches for nothing
  /// a process without an app bundle is refused, and starting it with the stream is what keeps the
  /// baseline honest — the first situation the client reports is the one the app came up in.
  func start() {
    client.start()
    ticker.start()
    announcements.start()
  }

  /// Claims the notification delegate and begins raising the reminder banner. Kept apart from
  /// `start()` because it reaches for `UNUserNotificationCenter.current()`, which no process
  /// without an app bundle may do.
  func startReminderResponder() {
    responder.start()
  }

}

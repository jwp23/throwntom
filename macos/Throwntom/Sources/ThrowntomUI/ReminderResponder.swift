import AppKit
import Observation
import ThrowntomClient
import UserNotifications

/// The app's whole side of a reminder: it raises the banner when the daemon starts waiting for an
/// answer, takes it down once the wait is over, and sends the daemon the command behind whichever
/// button the user pressed. macOS delivers a notification's response only to the process that posted
/// it, so the app that asks the question is also the one that answers it.
@Observable @MainActor
final class ReminderResponder: NSObject, UNUserNotificationCenterDelegate {

  // MARK: Lifecycle

  init(
    client: DaemonClient,
    authorizer: NotificationAuthorizer = SystemNotificationAuthorizer(),
    presenter: ReminderPresenter = SystemReminderPresenter(),
  ) {
    self.client = client
    self.authorizer = authorizer
    self.presenter = presenter
    super.init()
  }

  // MARK: Internal

  /// System Settings › Notifications, the only place a refusal can be undone.
  nonisolated static let notificationSettingsURL =
    URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

  /// How the reminder is shown while Throwntom is frontmost; otherwise macOS
  /// suppresses the banner and hides the only buttons the user has. `.sound` is here for the
  /// same reason: in the foreground macOS plays the banner's sound only when asked, and the
  /// daemon has none of its own to fall back on.
  nonisolated static let presentationOptions: UNNotificationPresentationOptions = [
    .banner,
    .list,
    .sound,
  ]

  /// What the window says about reminders macOS will not deliver. Silent until macOS answers.
  private(set) var authorization = ReminderAuthorization()

  /// Claims the delegate, puts the reminder's buttons on record, and starts following the daemon.
  /// Called from the app's initialiser: a banner posted before a delegate is in place has nowhere
  /// to deliver its answer.
  func start() {
    UNUserNotificationCenter.current().delegate = self
    presenter.registerReminderButtons()
    withdrawOnTermination()
    followDaemonState()
    Task {
      await requestAuthorization()
      await present(client.state)
    }
  }

  /// Raises and withdraws the banner as daemon state arrives. The window is closed or backgrounded
  /// almost all the time a reminder is due, so noticing one cannot depend on a view being on screen.
  func followDaemonState() {
    withObservationTracking {
      _ = client.state
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        followDaemonState()
        await present(client.state)
      }
    }
  }

  /// Shows what the daemon's latest state means for the banner. A state the app cannot read is
  /// not an answer to an outstanding reminder, so it leaves both the banner and the state that
  /// banner was decided from alone: reconnecting into the same wait posts and bounces nothing.
  func present(_ state: DaemonState?) async {
    guard let state else {
      withdrawIfTheServiceIsGone()
      return
    }
    chimeForNewRings(in: state)
    if ReminderBanner.wantsAttention(from: shownState, to: state) {
      presenter.requestAttention()
    }
    let banner = ReminderBanner.decide(from: shownState, to: state, authorization: authorization)
    shownState = state
    switch banner {
    case .post(let title, let body):
      do {
        try await presenter.postReminder(title: title, body: body)
      } catch {
        authorization = .rejected(error)
      }

    case .postMorning(let title, let body):
      do {
        try await presenter.postMorningReminder(title: title, body: body)
      } catch {
        authorization = .rejected(error)
      }

    case .withdraw:
      presenter.withdrawReminder()

    case .unchanged:
      break
    }
  }

  /// Takes the banner down when the app quits. macOS delivers a reminder's answer only to the
  /// process that posted it, so a banner outliving the app offers buttons that do nothing.
  func withdrawOnTermination() {
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: nil,
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.presenter.withdrawReminder() }
    }
  }

  /// Asks macOS to deliver reminders and keeps what it said. macOS shows the prompt as an
  /// ordinary banner in the corner of the screen, easy to miss with the window elsewhere on
  /// screen or closed entirely; a prompt that is never answered is recorded as a refusal and is
  /// never raised again. Keeping the answer is what turns that dead end into something the user
  /// can see and undo.
  func requestAuthorization() async {
    do {
      let granted = try await authorizer.requestAuthorization()
      authorization = .requested(granted: granted, error: nil)
    } catch {
      authorization = .requested(granted: false, error: error)
    }
  }

  /// Re-reads what macOS will do with a reminder now, so permission granted in System Settings
  /// clears the warning without a relaunch.
  func refreshAuthorization() async {
    authorization = .reported(await authorizer.authorizationStatus())
  }

  /// Opens where the refusal is undone. Nothing the app can do grants the permission back.
  func openNotificationSettings() {
    guard let url = Self.notificationSettingsURL else { return }
    NSWorkspace.shared.open(url)
  }

  /// Sends the daemon the command behind a reminder button, then reports back to macOS.
  /// Identifiers that name no button of ours — a plain click, a dismissal — still report
  /// back: macOS keeps the process alive until the handler runs.
  nonisolated func respond(to actionIdentifier: String, then completion: @escaping () -> Void) {
    guard let action = ReminderNotification.action(for: actionIdentifier) else {
      completion()
      return
    }
    Task { @MainActor in
      // The banner is the one dispatch path the user can reach without the window, so it needs
      // the same service gate every chip and menu item has. Without it a button pressed over a
      // stopped service sends a command that is refused, and the refusal lands in `commandError`,
      // which `unresolvedError` reports ahead of the stopped state — a fault note on the one
      // screen whose whole claim is that nothing failed.
      guard client.serviceStatus.offersDaemonCommands else {
        // Not silence. A button that disappears without doing what it says is a small lie, so the
        // press is answered with the window instead: it names which of the three service-down
        // situations this is and carries Start Timer Service. The banner goes with it, since the
        // question it asked cannot be answered until the service is back.
        withdrawIfTheServiceIsGone()
        presenter.showWindow()
        completion()
        return
      }
      do {
        try await ReminderNotification.answer(action, using: client)
      } catch {
        // Already recorded on `client` for the window's caption; nothing more to do here.
      }
      completion()
    }
  }

  nonisolated func userNotificationCenter(
    _ _: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void,
  ) {
    respond(to: response.actionIdentifier, then: completionHandler)
  }

  nonisolated func userNotificationCenter(
    _ _: UNUserNotificationCenter,
    willPresent _: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)
      -> Void,
  ) {
    completionHandler(Self.presentationOptions)
  }

  // MARK: Private

  private let client: DaemonClient
  private let authorizer: NotificationAuthorizer
  private let presenter: ReminderPresenter

  /// The daemon state the banner on screen was decided from.
  private var shownState: DaemonState?

  /// The ring count this app has already accounted for, or nil before it has read any state.
  /// Nil is what keeps a reconnect quiet: rings the app was not there to hear are adopted,
  /// not replayed as a burst of chimes.
  private var heardRings: Int?

  /// Takes the banner down once there is no service to answer it. A reminder outlives the daemon
  /// that raised it: macOS keeps it in Notification Center until something withdraws it, and
  /// stopping the service clears the state this responder follows, so no later frame arrives to
  /// retire it. Leaving it up offers buttons that cannot work.
  ///
  /// Forgetting `shownState` and `heardRings` with it is what makes the return quiet: the next
  /// daemon state is read as the first one rather than as a change from a wait that is long over,
  /// and rings counted by the old daemon are adopted rather than replayed.
  private func withdrawIfTheServiceIsGone() {
    guard !client.serviceStatus.offersDaemonCommands else { return }
    presenter.withdrawReminder()
    shownState = nil
    heardRings = nil
  }

  /// Sounds the repeats the daemon rang while the app was watching. Only a climb is a ring:
  /// the count resets when a wait is retired, and a reset is not something to be heard. The
  /// first ring of a wait is the banner's own sound, so it is counted here without chiming -
  /// otherwise a posting reminder would sound twice at once.
  private func chimeForNewRings(in state: DaemonState) {
    defer { heardRings = state.reminderRings }
    guard let heardRings, state.reminderRings > heardRings else { return }
    for _ in heardRings ..< state.reminderRings {
      presenter.chime()
    }
  }

}

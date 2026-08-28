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
  /// suppresses the banner and hides the only buttons the user has.
  nonisolated static var presentationOptions: UNNotificationPresentationOptions {
    [.banner, .list]
  }

  /// What the popover says about reminders macOS will not deliver. Silent until macOS answers.
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

  /// Raises and withdraws the banner as daemon state arrives. The popover is closed almost all the
  /// time a reminder is due, so noticing one cannot depend on a view being on screen.
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

  /// Shows what the daemon's latest state means for the banner.
  func present(_ state: DaemonState?) async {
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
  /// ordinary banner in the corner of the screen, which a menu bar app has nothing else to
  /// draw the eye to; a prompt that is never answered is recorded as a refusal and is never
  /// raised again. Keeping the answer is what turns that dead end into something the user can
  /// see and undo.
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
      try? await ReminderNotification.answer(action, using: client)
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

}

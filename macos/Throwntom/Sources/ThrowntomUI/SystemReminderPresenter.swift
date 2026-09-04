import AppKit
import ThrowntomClient
import UserNotifications

/// The real notification centre's reminder banner. A pass-through to `UNUserNotificationCenter`,
/// which no test process may reach: `UNUserNotificationCenter.current()` refuses to answer a
/// process without an app bundle. Everything that decides anything lives behind
/// `ReminderPresenter` instead, in `ReminderBanner`. Left out of coverage measurement for that
/// reason; see `sonar.coverage.exclusions` in sonar-project.properties.
final class SystemReminderPresenter: ReminderPresenter {

  // MARK: Lifecycle

  init() {
    // AppKit cancels an outstanding attention request when the app activates, but never tells
    // this side; without this, `requestAttention()`'s idempotency guard would see a stale
    // identifier and suppress every reminder after the first one the user ever saw.
    activationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil,
    ) { [weak self] _ in
      self?.attentionRequest = nil
    }
  }

  deinit {
    if let activationObserver {
      NotificationCenter.default.removeObserver(activationObserver)
    }
  }

  // MARK: Internal

  func registerReminderButtons() {
    UNUserNotificationCenter.current().setNotificationCategories([ReminderAlert.category, ReminderAlert.morningCategory])
  }

  func postReminder(title: String, body: String) async throws {
    try await UNUserNotificationCenter.current().add(ReminderAlert.request(title: title, body: body))
  }

  func postMorningReminder(title: String, body: String) async throws {
    try await UNUserNotificationCenter.current().add(ReminderAlert.morningRequest(title: title, body: body))
  }

  /// Takes the banner off screen whether the user has seen it or not: a reminder that has been
  /// answered must stop offering answers to it.
  func withdrawReminder() {
    let center = UNUserNotificationCenter.current()
    let pending = [ReminderNotification.requestIdentifier]
    center.removePendingNotificationRequests(withIdentifiers: pending)
    center.removeDeliveredNotifications(withIdentifiers: pending)

    // Activating the app cancels an attention request too, but an answer given without
    // activating (a notification button, or a reminder that lapses unanswered) must not leave
    // the Dock icon bouncing forever.
    cancelAttention()
  }

  /// Idempotent: a second call while a request is still outstanding would leak the first
  /// identifier, leaving `cancelAttention()` able to cancel only the newer one.
  func requestAttention() {
    guard attentionRequest == nil else { return }
    attentionRequest = NSApp.requestUserAttention(.criticalRequest)
  }

  func cancelAttention() {
    guard let attentionRequest else { return }
    NSApp.cancelUserAttentionRequest(attentionRequest)
    self.attentionRequest = nil
  }

  /// `orderFrontRegardless` is the whole implementation, and the two calls it is not are the
  /// point: `NSApp.activate` moves the app in front of the one the user is typing in, and
  /// `makeKeyAndOrderFront` hands it the keyboard. Joe rejected both outright (throwntom-lbw) —
  /// a nudge that arrives mid-sentence must not cost you your place. Ordering front regardless
  /// raises the window above other apps' windows while Throwntom stays inactive, so the
  /// explanation is there to read the moment they look, and their typing goes on where it was.
  ///
  /// The app has one window (ADR-005); `canBecomeKey` picks it out from any panel or helper
  /// without making it key. `isSheet` excludes the Keyboard Shortcuts sheet, which can also
  /// become key while it is up: `NSApp.windows` guarantees no ordering, so without that
  /// exclusion `first` could raise the sheet instead of the content window behind it. Nothing
  /// is created here, so a window the user closed stays closed.
  func showWindowWithoutFocus() {
    NSApp.windows.first { $0.canBecomeKey && !$0.isSheet }?.orderFrontRegardless()
  }

  /// One repeat of the reminder, played straight rather than through a second banner: the
  /// reminder already on screen is the one being repeated, and a banner per ring would leave
  /// the user a pile of them to dismiss. A missing sound is not worth failing over - the
  /// banner and the Dock still carry the reminder - so an unavailable name is simply quiet.
  func chime() {
    NSSound(named: chimeName)?.play()
  }

  // MARK: Private

  /// Glass is the sound the daemon used to play for a cycle reminder, so the repeat sounds
  /// the way it always has.
  private let chimeName = NSSound.Name("Glass")

  private var attentionRequest: Int?
  private var activationObserver: NSObjectProtocol?

}

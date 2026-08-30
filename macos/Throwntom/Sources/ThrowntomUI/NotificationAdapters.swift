import AppKit
import ThrowntomClient
import UserNotifications

// MARK: - SystemNotificationAuthorizer

/// The app's way through to `UNUserNotificationCenter`. Each type here is a pass-through to the
/// real notification centre, which no test process may reach: `UNUserNotificationCenter.current()`
/// refuses to answer a process without an app bundle. Everything that decides anything lives
/// behind the protocols instead, in `ReminderAuthorization` and `ReminderBanner`.
///
/// Gathered in one file so the boundary is visible, and so coverage can be measured on the part
/// that a test can actually run. See `sonar.coverage.exclusions` in sonar-project.properties.

/// The real notification centre's answers about permission.
struct SystemNotificationAuthorizer: NotificationAuthorizer {
  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// `.sound` is asked for because it is used: both reminder banners carry `content.sound`
  /// (`ReminderAlert.request`), which is silent without this permission. The repeat chime is
  /// `NSSound` and needs none of this.
  func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }
}

// MARK: - SystemReminderPresenter

/// The real notification centre's reminder banner.
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
    if let attentionRequest {
      NSApp.cancelUserAttentionRequest(attentionRequest)
      self.attentionRequest = nil
    }
  }

  /// Idempotent: a second call while a request is still outstanding would leak the first
  /// identifier, leaving `withdrawReminder()` able to cancel only the newer one.
  func requestAttention() {
    guard attentionRequest == nil else { return }
    attentionRequest = NSApp.requestUserAttention(.criticalRequest)
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

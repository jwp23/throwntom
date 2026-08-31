import UserNotifications

/// The real notification centre's answers about permission. A pass-through to
/// `UNUserNotificationCenter`, which no test process may reach: `UNUserNotificationCenter.current()`
/// refuses to answer a process without an app bundle. Everything that decides anything lives behind
/// `NotificationAuthorizer` instead, in `ReminderAuthorization`. Left out of coverage measurement
/// for that reason; see `sonar.coverage.exclusions` in sonar-project.properties.
struct SystemNotificationAuthorizer: NotificationAuthorizer {
  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// `.alert` only. Every sound a reminder makes is `NSSound` played by this app
  /// (`SystemReminderPresenter.chime()`), which needs no notification permission; the banners
  /// carry no `content.sound` for a `.sound` grant to apply to (ADR-009).
  func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
  }
}

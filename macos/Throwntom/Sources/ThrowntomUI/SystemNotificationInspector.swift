import AppKit
import Foundation
import ThrowntomClient
import UserNotifications

/// The real notification centre's account of itself, written to standard output as JSON so a
/// script or an agent can read it (`tools/notification-report.sh`).
///
/// A pass-through to `UNUserNotificationCenter`, which answers only the app it belongs to:
/// macOS keys a process's notification identity to the bundle whose `CFBundleExecutable` it is
/// running, so a helper binary beside the app — even inside the same bundle — is answered with a
/// blank record (`notDetermined`, everything `notSupported`) rather than with Throwntom's real
/// settings. That is why this runs in the app's own executable behind a flag instead of being a
/// tool of its own. Everything that decides anything lives in `NotificationReport`. Left out of
/// coverage measurement for the same reason as the other pass-throughs; see
/// `sonar.coverage.exclusions` in sonar-project.properties.
public enum SystemNotificationInspector {

  // MARK: Public

  /// Writes the report and answers with the process's exit status. Nothing else about the app
  /// starts: the window, the daemon connection and the reminder responder all belong to a run
  /// that was not asked a question.
  public static func writeReport() async -> Int32 {
    let report = await report()
    do {
      try FileHandle.standardOutput.write(contentsOf: Data((report.json() + "\n").utf8))
      return 0
    } catch {
      // A report that could not be written is a failure, not a report: the status says so rather
      // than leaving a reader with empty output and a success. It leaves the same trace every
      // other failure does — the operation and the error's shape in the unified log, a fixed
      // sentence for the person watching.
      ClientLog.failed("write the notification report", in: .reminders, error: error)
      try? FileHandle.standardError
        .write(contentsOf: Data("could not write the notification report; see the unified log\n".utf8))
      return 1
    }
  }

  // MARK: Private

  private static func report() async -> NotificationReport {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let delivered = await center.deliveredNotifications()
    return NotificationReport(
      authorization: settings.authorizationStatus,
      alerts: settings.alertSetting,
      sounds: settings.soundSetting,
      badges: settings.badgeSetting,
      alertStyle: settings.alertStyle,
      notificationCenter: settings.notificationCenterSetting,
      scheduledSummary: settings.scheduledDeliverySetting,
      runningApp: runningApp(),
      delivered: delivered.map(describe),
    )
  }

  /// Which copy of Throwntom macOS has running. This process is left out of the count: it is
  /// running the app's executable too, and a report that mistook itself for the app would say the
  /// reminders it cannot see are its own.
  private static func runningApp() -> NotificationReport.RunningApp {
    let identifier = Bundle.main.bundleIdentifier ?? ClientLog.subsystem
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
      .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
      .compactMap(\.bundleURL)
    return NotificationReport.RunningApp.of(bundle: Bundle.main.bundleURL, running: running)
  }

  /// Reduces a delivered notification to the three fields the report carries. The content is
  /// touched for one field, the category, which is a constant this app set (`ReminderAlert`) and
  /// the only thing that tells the cycle reminder from the morning nudge; the title and the body
  /// are the user's own business and are not read here or anywhere downstream.
  private static func describe(_ notification: UNNotification) -> NotificationReport.Delivered {
    NotificationReport.Delivered(
      identifier: notification.request.identifier,
      category: notification.request.content.categoryIdentifier,
      deliveredAt: notification.date,
    )
  }

}

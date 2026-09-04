import Foundation
import ThrowntomUI

// Asked for the notification report, this run answers it and stops. macOS gives a process the
// app's notification identity only when it is the bundle's own executable, so the question of
// what will happen to a reminder can be put to this binary and to nothing else
// (tools/notification-report.sh). The branch is here rather than in the app because the app's
// initialiser already opens the daemon connection and claims the notification delegate.
if NotificationReport.isRequested(CommandLine.arguments) {
  exit(await SystemNotificationInspector.writeReport())
}

ThrowntomApp.main()

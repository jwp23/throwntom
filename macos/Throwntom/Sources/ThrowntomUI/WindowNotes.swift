import SwiftUI

/// What went wrong, in sentences: a daemon error, or macOS refusing to deliver reminders. These
/// wrap rather than truncate because the sentence says what to do about it.
struct WindowNotes: View {
  let error: String?
  let responder: ReminderResponder

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let error {
        Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
      }
      if let problem = responder.authorization.problem {
        Text(problem).font(.caption).fixedSize(horizontal: false, vertical: true)
        Button("Open Notification Settings…") { responder.openNotificationSettings() }
      }
    }
  }
}

import SwiftUI

/// The sentences under the chips: why nothing is running, what went wrong, or macOS refusing to
/// deliver reminders. These wrap rather than truncate because the sentence says what to do about it.
struct WindowNotes: View {
  let error: String?
  /// Why the timer service is not running. Drawn first, and in the same weight as the faults
  /// below it rather than dimmed: it is the reading of the window and the reader needs it, and
  /// this ground's text carries its full colour so every line on it clears 4.5:1. What keeps it
  /// from looking like a crash is its wording, not a lighter grey.
  let notice: String?
  let responder: ReminderResponder

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let notice {
        Text(notice).font(.caption).fixedSize(horizontal: false, vertical: true)
      }
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

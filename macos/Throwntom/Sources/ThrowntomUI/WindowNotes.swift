import SwiftUI

/// The sentences under the chips: why nothing is running, what went wrong, or macOS refusing to
/// deliver reminders. These wrap rather than truncate because the sentence says what to do about it.
struct WindowNotes: View {
  let error: String?
  /// Why the timer service is not running. Drawn first, and in the same size and weight as the
  /// faults below it rather than dimmed or enlarged: this ground's text carries its full colour so
  /// every line on it clears 4.5:1, and the notes section is one register. What keeps a choice
  /// from reading as a crash is its wording, not a lighter grey — and what carries the weight on
  /// these screens is the title above, which already names the situation in full size. Growing
  /// this sentence would give the window two headlines.
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

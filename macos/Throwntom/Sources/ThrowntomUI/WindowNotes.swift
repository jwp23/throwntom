import SwiftUI

/// The sentences under the chips: why nothing is running, what went wrong, or macOS refusing to
/// deliver reminders. These wrap rather than truncate because the sentence says what to do about it.
struct WindowNotes: View {

  /// One register for the whole section, at the window's own text size. Body rather than caption
  /// because every line here is a sentence to act on, and a refusal is spelled out nowhere else on
  /// screen: the beep it arrives with says only that something did not happen (`DaemonDispatch`),
  /// and the title above goes on naming the phase. The smallest type in the window is the wrong
  /// place for the only account of it. Still far below the headline, so this gives the window no
  /// second headline; what it stops is a refusal being harder to read than the shortcut hint under
  /// a panel (throwntom-bxd.14).
  static let font = Font.body

  let error: String?
  /// Why the timer service is not running. Drawn first, and in the same size and weight as the
  /// faults below it rather than dimmed or singled out: this ground's text carries its full colour
  /// so every line on it clears 4.5:1, and the notes section is one register. What keeps a choice
  /// from reading as a crash is its wording, not a lighter grey — and what carries the weight on
  /// these screens is the title above, which already names the situation in full size.
  let notice: String?
  let responder: ReminderResponder

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let notice {
        Text(notice).font(Self.font).fixedSize(horizontal: false, vertical: true)
      }
      if let error {
        Text(error).font(Self.font).fixedSize(horizontal: false, vertical: true)
      }
      if let problem = responder.authorization.problem {
        Text(problem).font(Self.font).fixedSize(horizontal: false, vertical: true)
        Button("Open Notification Settings…") { responder.openNotificationSettings() }
      }
    }
  }

}

import AppKit
import SwiftUI
import ThrowntomClient

/// The field behind the meeting chip's `Custom…`: how many minutes, in a row that opens under
/// the chips and closes as soon as it is answered. Return commits, Escape abandons — the same
/// contract `SnoozeEntryRow` and the inline new-task row keep, because these are the only places
/// this app asks for typing and a rule that differed between them is a rule learned twice.
struct MeetingEntryRow: View {

  // MARK: Internal

  let client: DaemonClient
  let model: WindowModel
  /// Injected so a refusal is observable in a test instead of only audible.
  var alert: () -> Void = { NSSound.beep() }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text("Meeting for")
        field
        Text("minutes")
      }
      rule
    }
  }

  /// Painted in the app's own paper for the reason the snooze field is: a system-drawn bezel
  /// takes the system appearance's background while the text on it takes this window's ink.
  var field: some View {
    TextField("minutes", text: $text)
      .textFieldStyle(.plain)
      .foregroundStyle(Palette.ink.color)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Palette.cream.color, in: RoundedRectangle(cornerRadius: 6))
      .frame(width: 70)
      .focused($isFocused)
      .accessibilityLabel("Meeting length in minutes")
      .onAppear { isFocused = true }
      .onSubmit { submit(text) }
      .onExitCommand { model.isEnteringMeeting = false }
  }

  /// The rule in full text rather than a dimmed caption, for the reason the snooze row states
  /// its own: this is the line a user reads *because* what they typed was refused.
  var rule: some View {
    Text("1 to \(Minutes.maximum) minutes")
      .font(.caption)
  }

  /// Commits a typed length, or refuses it and leaves the field open with the text intact so a
  /// typo can be corrected rather than retyped.
  func submit(_ entry: String) {
    guard let minutes = Minutes.parse(entry) else {
      alert()
      return
    }
    DaemonDispatch.perform(.start(minutes: minutes), on: client)
    text = ""
    model.isEnteringMeeting = false
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool

}

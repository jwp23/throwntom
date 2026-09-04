import AppKit
import SwiftUI
import ThrowntomClient

/// The field behind `Custom…`: how many minutes, in a row that opens under the chips and closes
/// as soon as it is answered. Return commits, Escape abandons — the same contract as the inline
/// new-task row, which is the only other place this app asks for typing.
struct SnoozeEntryRow: View {

  // MARK: Internal

  let client: DaemonClient
  let model: WindowModel
  /// Injected so a refusal is observable in a test instead of only audible.
  var alert: () -> Void = { NSSound.beep() }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text("Snooze for")
        field
        Text("minutes")
      }
      rule
    }
  }

  /// Built as its own property, out of the stack, so what it is drawn in can be asserted on its
  /// own rather than only through the (untestable) rendering pass.
  ///
  /// Painted in the app's own paper rather than the system's: a bezel the system draws takes the
  /// system appearance's background, while the text on it takes this window's ink — black on black
  /// in Dark Mode. Cream under ink is the icon's own pairing and reads as something to type in on
  /// every phase ground, whatever the system is set to.
  var field: some View {
    TextField("minutes", text: $text)
      .textFieldStyle(.plain)
      .foregroundStyle(Palette.ink.color)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(Palette.cream.color, in: RoundedRectangle(cornerRadius: 6))
      .frame(width: 70)
      .focused($isFocused)
      .accessibilityLabel("Snooze duration in minutes")
      .onAppear { isFocused = true }
      .onSubmit { submit(text) }
      .onExitCommand { model.isEnteringSnooze = false }
  }

  /// Stating the rule beats a beep that leaves the user guessing which part was wrong. A caption,
  /// but not a dimmed one: this ground's text carries its full colour so every line on it clears
  /// 4.5:1 — the same call `WindowNotes` makes — and this is the line a user reads *because* the
  /// duration they typed was refused.
  var rule: some View {
    Text("1 to \(Minutes.maximum) minutes")
      .font(.caption)
  }

  /// Commits a typed duration, or refuses it and leaves the field open with the text intact so a
  /// typo can be corrected rather than retyped. Takes the entry rather than reading the field, so
  /// the decision can be exercised without a view hierarchy to hold the field's state.
  func submit(_ entry: String) {
    guard let minutes = Minutes.parse(entry) else {
      alert()
      return
    }
    DaemonDispatch.perform(.snooze(minutes: minutes), on: client)
    text = ""
    model.isEnteringSnooze = false
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool

}

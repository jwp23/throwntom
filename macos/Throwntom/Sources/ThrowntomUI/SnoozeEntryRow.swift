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
        TextField("minutes", text: $text)
          .textFieldStyle(.roundedBorder)
          .frame(width: 70)
          .focused($isFocused)
          .accessibilityLabel("Snooze duration in minutes")
          .onAppear { isFocused = true }
          .onSubmit { submit(text) }
          .onExitCommand { model.isEnteringSnooze = false }
        Text("minutes")
      }
      // Stating the rule beats a beep that leaves the user guessing which part was wrong.
      Text("1 to \(SnoozeDraft.maximumMinutes) minutes")
        .foregroundStyle(.secondary)
    }
    .font(.caption)
  }

  /// Commits a typed duration, or refuses it and leaves the field open with the text intact so a
  /// typo can be corrected rather than retyped. Takes the entry rather than reading the field, so
  /// the decision can be exercised without a view hierarchy to hold the field's state.
  func submit(_ entry: String) {
    guard let minutes = SnoozeDraft.minutes(from: entry) else {
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

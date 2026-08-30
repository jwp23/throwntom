import AppKit
import SwiftUI
import ThrowntomClient

// MARK: - SnoozeEntry

/// What a typed custom duration means. Kept apart from the field so the rule — a whole number of
/// minutes or nothing — is one testable decision rather than a condition buried in a view.
enum SnoozeEntry {
  enum Outcome: Equatable {
    case snooze(minutes: Int)
    case refuse
  }

  static func commit(_ text: String) -> Outcome {
    guard let minutes = SnoozeDraft.minutes(from: text) else { return .refuse }
    return .snooze(minutes: minutes)
  }
}

// MARK: - SnoozeChip

/// The snooze control: a chip that defers the reminder on a plain click and opens the durations
/// on a press-and-hold, the way a macOS pull-down with a default action behaves.
///
/// While a snooze is running the same chip cancels it, because that is the moment the user wants
/// the undo and going looking for a second control for it is the gap this closes. The durations
/// stay in the menu either way, so a snooze can be lengthened without first being cancelled.
struct SnoozeChip: View {

  // MARK: Internal

  let content: MainWindowContent
  let client: DaemonClient
  let model: WindowModel

  var isSnoozed: Bool {
    content.snoozeNote != nil
  }

  var title: String {
    isSnoozed ? SnoozeAction.cancel.title : "Snooze"
  }

  /// A plain click takes the obvious answer for the current state: defer for the default, or, if
  /// the reminder is already deferred, bring it back.
  var primaryAction: SnoozeAction {
    isSnoozed ? .cancel : .snooze(minutes: SnoozeActions.defaultMinutes)
  }

  var body: some View {
    Menu {
      MenuGroups(menu: MenuModel.snooze(state: client.state)) { item in
        Button(item.title) { run(item.action) }
          .disabled(!item.isEnabled)
      }
    } label: {
      ChipLabel(title: title, hint: TimerAction.snooze.shortcutHint, style: style)
    } primaryAction: {
      run(primaryAction)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel(title)
  }

  /// Runs a snooze verb, except `Custom…`, which is a question for the user rather than a command
  /// for the daemon: it opens the field, and the answer arrives as an ordinary snooze.
  func run(_ action: SnoozeAction) {
    if action == .custom {
      model.isEnteringSnooze = true
    } else {
      DaemonDispatch.perform(action, on: client)
    }
  }

  // MARK: Private

  private var style: ChipStyle {
    ChipStyle.style(primary: false, scheme: content.scheme)
  }

}

// MARK: - SnoozeEntryRow

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
    HStack(spacing: 6) {
      Text("Snooze for")
      TextField("minutes", text: $text)
        .textFieldStyle(.roundedBorder)
        .frame(width: 70)
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onSubmit { submit() }
        .onExitCommand { model.isEnteringSnooze = false }
      Text("minutes")
    }
    .font(.caption)
  }

  /// Commits the typed duration, or refuses it and leaves the field open with the text intact so
  /// a typo can be corrected rather than retyped.
  func submit() {
    switch SnoozeEntry.commit(text) {
    case .snooze(let minutes):
      DaemonDispatch.perform(.snooze(minutes: minutes), on: client)
      text = ""
      model.isEnteringSnooze = false

    case .refuse:
      alert()
    }
  }

  // MARK: Private

  @State private var text = ""
  @FocusState private var isFocused: Bool

}

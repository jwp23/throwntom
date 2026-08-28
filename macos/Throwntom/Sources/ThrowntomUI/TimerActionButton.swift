import SwiftUI
import ThrowntomClient

// MARK: - TimerActionButtonLayout

/// Where a `TimerActionButton` is placed: the popover's vertical menu can right-align the
/// shortcut hint with an expanding `Spacer`, but that same `Spacer` breaks a toolbar item's
/// layout, so the toolbar relies on the `.help` tooltip instead.
enum TimerActionButtonLayout {
  case popover
  case toolbar
}

// MARK: - TimerActionButton

/// One timer verb as a button; the same control is used in the popover and the task window toolbar.
struct TimerActionButton: View {
  let action: TimerAction
  let client: DaemonClient
  var layout = TimerActionButtonLayout.popover

  /// True only in the popover, and only when the action has a hint to show.
  var showsInlineHint: Bool {
    layout == .popover && !action.shortcutHint.isEmpty
  }

  var body: some View {
    Button {
      Task { await perform() }
    } label: {
      if showsInlineHint {
        HStack {
          Text(action.title)
          Spacer()
          Text(action.shortcutHint).foregroundStyle(.secondary)
        }
      } else {
        Text(action.title)
      }
    }
    .help(action.helpText)
  }

  func perform() async {
    do { try await client.perform(action) } catch { NSSound.beep() }
  }
}

import SwiftUI
import ThrowntomClient

/// The timer verbs valid right now, as chips; the primary one (start, confirm, resume) stands out.
/// Flowed into rows, like the command chips below, so a state with several verbs still fits a
/// 320pt window instead of running past its edge.
struct ActionChips: View {
  let content: MainWindowContent
  let client: DaemonClient
  let model: WindowModel

  var body: some View {
    BlockFlowLayout.chipRow {
      ForEach(content.chips, id: \.self) { action in
        row(for: action)
      }
    }
  }

  /// Snooze is the one verb with a duration to choose and an undo to offer, so it is a pull-down
  /// rather than a plain button. Everything else is one click and done. Built as its own method,
  /// free of `ForEach`'s trailing closure, for the same testability reason as `chip(for:)`.
  @ViewBuilder
  func row(for action: TimerAction) -> some View {
    if action == .snooze {
      SnoozeChip(content: content, client: client, model: model)
    } else {
      chip(for: action)
    }
  }

  /// Built as its own method, free of `ForEach`'s trailing closure, so it can be called and
  /// asserted on directly instead of only through the (untestable) rendering pass.
  func chip(for action: TimerAction) -> Chip {
    Chip(
      title: action.title,
      hint: action.shortcutHint,
      isPrimary: action == content.primaryChip,
      scheme: content.scheme,
    ) {
      DaemonDispatch.perform(action, on: client)
    }
  }
}

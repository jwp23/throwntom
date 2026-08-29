import SwiftUI
import ThrowntomClient

/// The timer verbs valid right now, as chips; the primary one (start, confirm, resume) stands out.
struct ActionChips: View {
  let content: MainWindowContent
  let client: DaemonClient

  var body: some View {
    HStack(spacing: 6) {
      ForEach(content.chips, id: \.self) { action in
        chip(for: action)
      }
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

import SwiftUI
import ThrowntomClient

/// The timer verbs valid right now, as chips; the primary one (start, confirm, resume) stands out.
/// Flowed into rows, like the command chips below, so a state with several verbs still fits a
/// 320pt window instead of running past its edge.
struct ActionChips: View {
  let content: MainWindowContent
  let client: DaemonClient

  /// Named so a test can hold this row to the same layout the command row uses.
  var layout: BlockFlowLayout {
    .chipRow
  }

  var body: some View {
    layout {
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

import SwiftUI
import ThrowntomClient

/// The window's Start/Stop control for the timer service (ADR-006). It sits under the timer verbs
/// on every screen rather than only on the stopped one, because quitting the app does not stop the
/// daemon and the only way to stop it has to be somewhere the user can find it. While the service
/// is stopped or refusing to launch there are no timer verbs above, so Start stands alone and
/// carries the primary weight.
struct ServiceChip: View {

  let content: MainWindowContent
  let client: DaemonClient

  /// Built as its own property, free of any view builder, so it can be called and asserted on
  /// directly instead of only through the (untestable) rendering pass.
  var chip: Chip {
    Chip(
      title: content.serviceAction.title,
      hint: content.serviceAction.shortcutHint,
      isPrimary: content.serviceAction == .start,
      scheme: content.scheme,
    ) {
      DaemonDispatch.control(content.serviceAction, on: client)
    }
  }

  var body: some View {
    chip
  }

}

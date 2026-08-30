import AppKit
import SwiftUI
import ThrowntomClient

// MARK: - WindowElevation

/// Whether the window sits above other applications' windows, and how that is applied.
///
/// A reminder is easy to lose behind a cluttered screen, and the Dock bounce is easy to miss. The
/// window level fixes that without a popup: it changes which window is on top and nothing else.
enum WindowElevation {

  /// Whether the window should be above other applications right now. Off unless the user asked
  /// for it (`float_window_when_waiting`, default false) and a reminder is actually outstanding —
  /// a window that stayed in front once the wait was over would be an interruption with no
  /// reminder behind it.
  ///
  /// A state the app cannot read is not a wait, so a lost daemon lets the window back down.
  static func floats(during state: DaemonState?) -> Bool {
    guard let state, state.floatWindowWhenWaiting else { return false }
    return ReminderBanner.isWaiting(state)
  }

  /// Applies the level. Nothing here activates the app or orders the window front: those are what
  /// take the keyboard, and a reminder that stole focus mid-sentence would cost the user more than
  /// a reminder they had to go looking for. The level is a stacking order, not a focus change.
  static func apply(_ floating: Bool, to window: NSWindow) {
    window.level = floating ? .floating : .normal
  }

}

// MARK: - WindowElevator

/// Applies `WindowElevation` to the window the view is in. SwiftUI's `Window` scene exposes no
/// window level of its own, and the `NSWindow` behind it is reachable only from a hosted view.
struct WindowElevator: NSViewRepresentable {
  let floating: Bool

  func makeNSView(context _: Context) -> NSView {
    NSView()
  }

  /// A view has no window until it is in the hierarchy, and on the first update it is not yet.
  /// Asking again on the next turn of the run loop is what makes the level stick on launch.
  func updateNSView(_ view: NSView, context _: Context) {
    let floating = floating
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      WindowElevation.apply(floating, to: window)
    }
  }
}

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
  /// Only a live connection floats the window. A lost daemon leaves the last state it sent behind,
  /// and that state can say a reminder is waiting; keeping the window in front on the strength of
  /// it would leave the window floating over everything for as long as the daemon stayed down,
  /// with nothing able to answer the reminder and take it back down. The banner is deliberately
  /// left up in that situation, because it is answerable later; the window level is not.
  static func floats(during state: DaemonState?, connection: DaemonClient.Connection) -> Bool {
    guard let state, connection == .connected, state.floatWindowWhenWaiting else { return false }
    return ReminderBanner.isWaiting(state)
  }

  /// Applies the level. Nothing here activates the app or orders the window front: those are what
  /// take the keyboard, and a reminder that stole focus mid-sentence would cost the user more than
  /// a reminder they had to go looking for. The level is a stacking order, not a focus change.
  ///
  /// Setting the level re-orders the window with the window server, so an unchanged level is left
  /// alone: the window's view is rebuilt every second by the countdown, and this is asked each time.
  static func apply(_ floating: Bool, to window: NSWindow) {
    let level: NSWindow.Level = floating ? .floating : .normal
    guard window.level != level else { return }
    window.level = level
  }

}

// MARK: - ElevatedHostView

/// Carries the window level for `WindowElevator`. A view has no window until it joins the
/// hierarchy, and AppKit says when that happens — so the level is applied on that event rather
/// than guessed at from a later turn of the run loop. Moving to another window re-applies it.
final class ElevatedHostView: NSView {

  // MARK: Internal

  var floating = false {
    didSet {
      guard floating != oldValue else { return }
      applyLevel()
    }
  }

  /// Nothing is drawn or clicked here: this view exists to reach the window behind it.
  override var isOpaque: Bool {
    false
  }

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    applyLevel()
  }

  // MARK: Private

  private func applyLevel() {
    guard let window else { return }
    WindowElevation.apply(floating, to: window)
  }

}

// MARK: - WindowElevator

/// Applies `WindowElevation` to the window the view is in. SwiftUI's `Window` scene exposes no
/// window level of its own, and the `NSWindow` behind it is reachable only from a hosted view.
/// macOS 15 added a scene-level `windowLevel(_:)` that would replace this; the app targets 14.
struct WindowElevator: NSViewRepresentable {
  let floating: Bool

  func makeNSView(context _: Context) -> ElevatedHostView {
    ElevatedHostView()
  }

  func updateNSView(_ view: ElevatedHostView, context _: Context) {
    view.floating = floating
  }
}

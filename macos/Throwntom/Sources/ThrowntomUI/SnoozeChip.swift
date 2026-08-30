import SwiftUI
import ThrowntomClient

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

  /// ⌘⇧S snoozes; nothing binds the undo. The chip advertises the key only while it is the thing
  /// the key does, so it never offers a keystroke that would do the opposite of what it says.
  var hint: String {
    isSnoozed ? "" : TimerAction.snooze.shortcutHint
  }

  /// Built from what the window already decided rather than from the daemon state again, so the
  /// chip's face and its menu can never disagree about whether a snooze is running. `canDefer` is
  /// unconditionally true because this chip is only rendered for a state that offers Snooze — the
  /// menu bar's copy of this menu is the one that has to work that out.
  var menu: MenuModel<SnoozeAction> {
    MenuModel.snooze(canDefer: true, isSnoozed: isSnoozed)
  }

  var body: some View {
    Menu {
      MenuGroups(menu: menu) { item in
        Button(item.title) { run(item.action) }
          .disabled(!item.isEnabled)
      }
    } label: {
      ChipLabel(title: title, hint: hint, style: style)
    } primaryAction: {
      run(primaryAction)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityLabel(hint.isEmpty ? title : "\(title), \(hint)")
    .accessibilityHint("Press and hold to choose how long")
  }

  /// Runs a snooze verb, except `Custom…`, which is a question for the user rather than a command
  /// for the daemon: it opens the field, and the answer arrives as an ordinary snooze.
  func run(_ action: SnoozeAction) {
    guard let request = action.request else {
      model.isEnteringSnooze = true
      return
    }
    DaemonDispatch.perform(request, on: client)
  }

  // MARK: Private

  private var style: ChipStyle {
    ChipStyle.style(primary: false, scheme: content.scheme)
  }

}

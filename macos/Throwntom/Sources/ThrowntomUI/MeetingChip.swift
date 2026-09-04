import SwiftUI
import ThrowntomClient

/// The meeting control: a chip that starts a meeting of the default length on a plain click and
/// opens the lengths on a press-and-hold, the way the snooze chip does.
///
/// While a meeting is running the same chip ends it, because that is the moment the user wants
/// the way out and going looking for a second control for it is the gap this closes. It is not
/// the Skip chip in a different coat: the daemon credits the time spent in a meeting that is
/// ended early, so this ends something the user did rather than discarding it, and a running
/// meeting offers no Skip beside it (`TimerActions.available(for:)`).
struct MeetingChip: View {

  // MARK: Internal

  let content: MainWindowContent
  let client: DaemonClient
  let model: WindowModel

  var isMeeting: Bool {
    content.isMeeting
  }

  var title: String {
    isMeeting ? MeetingAction.end.title : TimerAction.meeting.title
  }

  /// A plain click takes the obvious answer for the current state: go into a meeting of the
  /// default length, or, if one is already running, come out of it.
  var primaryAction: MeetingAction {
    isMeeting ? .end : .start(minutes: MeetingActions.defaultMinutes)
  }

  /// The lengths stay in the menu while a meeting runs, so one can be lengthened — or restarted
  /// at a new length when it overruns — without first being ended.
  var menu: MenuModel<MeetingAction> {
    MenuModel.meeting(canStart: true, isMeeting: isMeeting)
  }

  var body: some View {
    Menu {
      MenuGroups(menu: menu) { item in menuButton(for: item) }
    } label: {
      ChipLabel(title: title, hint: "", style: style)
    } primaryAction: {
      run(primaryAction)
    }
    // AppKit's own menu style repaints the label; the button style keeps ChipLabel's paint, so
    // the pull-down wears the same chip as the buttons beside it.
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel(title)
    .accessibilityHint("Press and hold to choose how long")
  }

  /// Built as its own method, free of the menu's trailing closure, so a test can call it directly
  /// rather than only through a rendering pass.
  func menuButton(for item: MenuItem<MeetingAction>) -> some View {
    Button(item.title) { run(item.action) }
      .disabled(!item.isEnabled)
  }

  func run(_ action: MeetingAction) {
    guard let request = action.request else {
      model.isEnteringMeeting = true
      return
    }
    DaemonDispatch.perform(request, on: client)
  }

  // MARK: Private

  /// Secondary like the verbs beside it: a meeting is something that happens to the user, never
  /// the thing the window is asking them to press.
  private var style: ChipStyle {
    ChipStyle.style(primary: false, scheme: content.scheme)
  }

}

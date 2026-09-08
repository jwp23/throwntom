import SwiftUI
import ThrowntomClient

/// The lunch control: a chip that takes the daemon's configured length on a plain click and
/// opens the lengths on a click of its trailing chevron, the way the meeting chip does.
///
/// Unlike meeting, lunch needs no way out of its own: `TimerActions.available(for:)` already
/// withdraws this chip once a lunch is running and offers Skip in its place, so this chip never
/// has to explain how to leave what it started.
struct LunchChip: View {

  // MARK: Internal

  let content: MainWindowContent
  let client: DaemonClient
  let model: WindowModel

  var title: String {
    TimerAction.lunch.title
  }

  var menu: MenuModel<LunchAction> {
    MenuModel.lunch(canStart: true)
  }

  var body: some View {
    SplitChip(
      title: title,
      hint: "",
      style: style,
      menu: menu,
      menuAccessibilityLabel: "Lunch",
      primaryAction: { run(nil) },
    ) { item in
      menuButton(for: item)
    }
  }

  /// Built as its own method, free of the menu's trailing closure, so a test can call it directly
  /// rather than only through a rendering pass.
  func menuButton(for item: MenuItem<LunchAction>) -> some View {
    Button(item.title) { run(item.action) }
      .disabled(!item.isEnabled)
  }

  /// A plain click (`action` nil) sends no explicit length at all — the config-default path a
  /// bare `lunch` verb takes — rather than one of the picker's presets the user never chose.
  func run(_ action: LunchAction?) {
    guard let action else {
      DaemonDispatch.perform(TimerAction.lunch, on: client)
      return
    }
    guard let request = action.request else {
      model.beginEntry(.lunch)
      return
    }
    DaemonDispatch.perform(request, on: client)
  }

  // MARK: Private

  /// Secondary like the verbs beside it: lunch is something the user reaches for, never the
  /// thing the window is asking them to press.
  private var style: ChipStyle {
    ChipStyle.style(primary: false, scheme: content.scheme)
  }

}

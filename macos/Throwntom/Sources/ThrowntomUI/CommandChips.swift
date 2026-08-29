import SwiftUI

/// The window's own way to the commands the menu bar also carries: the tasks and stats panels, the
/// cheat sheet and the config file. Always secondary — the timer verbs above own the primary
/// weight — and flowed into rows so the longest title still fits a 320pt window.
struct CommandChips: View {

  let environment: AppEnvironment
  let scheme: PhaseScheme

  var menu: MenuModel<ViewAction> {
    MenuModel.windowCommands(model: environment.windowModel)
  }

  var body: some View {
    BlockFlowLayout(blockGap: 6, rowSpacing: 6) {
      ForEach(menu.items) { item in
        chip(for: item)
      }
    }
  }

  /// Built as its own method, free of `ForEach`'s trailing closure, so it can be called and
  /// asserted on directly instead of only through the (untestable) rendering pass.
  func chip(for item: MenuItem<ViewAction>) -> Chip {
    Chip(title: item.title, hint: item.action.shortcutHint, isPrimary: false, scheme: scheme) {
      ViewActionDispatch.show(item.action, in: environment.windowModel)
    }
  }

}

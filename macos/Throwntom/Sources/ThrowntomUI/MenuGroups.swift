import SwiftUI

/// A `MenuModel` rendered as its groups with a divider between them. The caller supplies the
/// button for each item, so the same shape serves the menu bar and a row's context menu.
struct MenuGroups<Action: MenuAction, Label: View>: View {
  let menu: MenuModel<Action>
  @ViewBuilder let label: (MenuItem<Action>) -> Label

  var body: some View {
    ForEach(Array(menu.groups.enumerated()), id: \.offset) { index, group in
      groupView(index: index, group: group)
    }
  }

  /// Built as its own method, free of `ForEach`'s trailing closure, so the divider placement can
  /// be called and asserted on directly instead of only through the (untestable) rendering pass.
  @ViewBuilder
  func groupView(index: Int, group: [MenuItem<Action>]) -> some View {
    if index > 0 {
      Divider()
    }
    ForEach(group) { item in
      label(item)
    }
  }
}

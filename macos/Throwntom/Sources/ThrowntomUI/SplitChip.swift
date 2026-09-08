import SwiftUI

/// A chip with two independently-clickable regions sharing one fill: the label performs the
/// chip's plain-click action, and the chevron opens a menu on a plain click (throwntom-bxd.29).
/// Built entirely of SwiftUI's own drawing rather than a native combo/split button, because
/// AppKit's own split-button chrome does not take this app's palette — it renders as a light
/// system-grey pill against this app's dark `*-chip` colours.
struct SplitChip<Action: MenuAction, MenuItemLabel: View>: View {

  // MARK: Internal

  let title: String
  let hint: String
  let style: ChipStyle
  let menu: MenuModel<Action>
  let primaryAction: () -> Void
  @ViewBuilder let menuItemLabel: (MenuItem<Action>) -> MenuItemLabel

  var body: some View {
    HStack(spacing: 0) {
      labelRegion
      chevronRegion
    }
    .background(style.fill.color, in: RoundedRectangle(cornerRadius: 6))
    .foregroundStyle(style.text.color)
  }

  // MARK: Private

  private var labelRegion: some View {
    Button(action: primaryAction) {
      ChipFace(title: title, hint: hint)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(hint.isEmpty ? title : "\(title), \(hint)")
  }

  private var chevronRegion: some View {
    Menu {
      MenuGroups(menu: menu, label: menuItemLabel)
    } label: {
      Image(systemName: "chevron.down")
        .font(.caption2.weight(.semibold))
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel("\(title) options")
    .accessibilityHint("Opens the duration menu")
  }

}

import SwiftUI

/// A chip with two independently-clickable regions sharing one fill: the label performs the
/// chip's plain-click action, and the chevron opens a menu on a plain click — no press-and-hold
/// anywhere (throwntom-bxd.29). Built entirely of SwiftUI's own drawing rather than a native
/// combo/split button, because AppKit's own split-button chrome does not take this app's
/// palette — it renders as a light system-grey pill against this app's dark `*-chip` colours,
/// which is what left the plain `Menu(primaryAction:)` chevron a press-and-hold-only control in
/// the first place once `throwntom-bxd.2` moved its label off AppKit's own drawing.
struct SplitChip<Action: MenuAction, MenuItemLabel: View>: View {

  // MARK: Internal

  let title: String
  let hint: String
  let style: ChipStyle
  let menu: MenuModel<Action>
  /// The chevron's own accessibility name — a stable verb ("Snooze", not "Cancel Snooze"),
  /// independent of `title`, which changes with the chip's running state. The chevron always
  /// opens the same kind of menu (durations, sometimes a way out) regardless of that state, so
  /// its own label should not change with it either.
  let menuAccessibilityLabel: String
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
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityLabel("\(menuAccessibilityLabel) options")
    .accessibilityHint("Opens the duration menu")
  }

}

import SwiftUI

// MARK: - ChipStyle

/// The primary verb is the icon's outline brown with a cream label; every other verb is the phase
/// ground under black with a white label.
struct ChipStyle: Equatable {
  let fill: HexColor
  let text: HexColor

  static func style(primary: Bool, scheme: PhaseScheme) -> ChipStyle {
    primary
      ? ChipStyle(fill: scheme.primaryChip, text: scheme.primaryChipText)
      : ChipStyle(fill: scheme.secondaryChip, text: scheme.secondaryChipText)
  }
}

// MARK: - Chip

/// A rounded button showing its title and, when it has one, its keyboard shortcut. The shortcut
/// itself is bound in the menus; the chip only advertises it.
struct Chip: View {

  // MARK: Lifecycle

  init(title: String, hint: String, isPrimary: Bool, scheme: PhaseScheme, action: @escaping () -> Void) {
    self.title = title
    self.hint = hint
    style = ChipStyle.style(primary: isPrimary, scheme: scheme)
    self.action = action
  }

  // MARK: Internal

  let title: String
  let hint: String
  let style: ChipStyle
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(title).fontWeight(.semibold)
        if !hint.isEmpty {
          Text(hint).font(.body.monospaced())
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(style.fill.color, in: RoundedRectangle(cornerRadius: 6))
      .foregroundStyle(style.text.color)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(hint.isEmpty ? title : "\(title), \(hint)")
  }

}

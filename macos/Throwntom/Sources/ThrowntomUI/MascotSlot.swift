import SwiftUI

/// The cream square beside the phase name. It holds a glyph for now and is sized for the mascot
/// that will replace it, so nothing around it moves when that lands.
struct MascotSlot: View {
  static let size: CGFloat = 72

  let glyph: MascotGlyph
  let scheme: PhaseScheme

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10)
        .fill(scheme.slot.color)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.outline.color, lineWidth: 1.5))
      switch glyph {
      case .emoji(let emoji):
        Text(emoji).font(.system(size: 40))
      case .symbol(let name):
        Image(systemName: name)
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(Palette.outline.color)
      }
    }
    .frame(width: Self.size, height: Self.size)
    .accessibilityHidden(true)
  }
}

import SwiftUI

struct MascotSlot: View {

  // MARK: Internal

  static let size: CGFloat = 72

  let glyph: MascotGlyph
  let scheme: PhaseScheme
  let pulsing: Bool

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
    .scaleEffect(animates && beat ? 1.08 : 1)
    .animation(animates ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: beat)
    .onChange(of: animates, initial: true) { _, on in beat = on }
    .accessibilityHidden(true)
  }

  // MARK: Private

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var beat = false

  /// Pulse only while a phase waits, and never for a user who asked macOS for less motion.
  private var animates: Bool {
    pulsing && !reduceMotion
  }

}

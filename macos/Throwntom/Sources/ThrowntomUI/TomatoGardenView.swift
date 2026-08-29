import SwiftUI

/// Today's pomodoros as rows of tomato blocks, wrapped to the width the window gives it.
struct TomatoGardenView: View {

  static let glyphWidth: CGFloat = 32
  static let blockGap: CGFloat = 16

  let garden: TomatoGarden

  var body: some View {
    VStack(spacing: 4) {
      BlockFlowLayout(blockGap: Self.blockGap, rowSpacing: 4) {
        ForEach(Array(garden.blocks.enumerated()), id: \.offset) { _, block in
          HStack(spacing: 0) {
            ForEach(Array(block.enumerated()), id: \.offset) { _, filled in
              Text("🍅").font(.system(size: 26)).opacity(filled ? 1 : 0.35).frame(width: Self.glyphWidth)
            }
          }
        }
      }
      Text(garden.summary).font(.body)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(garden.summary)
  }

}

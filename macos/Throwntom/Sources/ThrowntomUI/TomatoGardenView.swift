import SwiftUI

/// Today's pomodoros as rows of tomato blocks, wrapped to the width the window gives it.
struct TomatoGardenView: View {

  static let glyphWidth: CGFloat = 20
  static let blockGap: CGFloat = 12

  let garden: TomatoGarden

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      BlockFlowLayout(blockGap: Self.blockGap, rowSpacing: 4) {
        ForEach(Array(garden.blocks.enumerated()), id: \.offset) { _, block in
          HStack(spacing: 0) {
            ForEach(Array(block.enumerated()), id: \.offset) { _, filled in
              Text("🍅").font(.system(size: 16)).opacity(filled ? 1 : 0.35).frame(width: Self.glyphWidth)
            }
          }
        }
      }
      Text(garden.summary).font(.caption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(garden.summary)
  }

}

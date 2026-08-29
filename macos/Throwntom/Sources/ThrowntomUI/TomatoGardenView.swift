import SwiftUI

/// Today's pomodoros as rows of tomato blocks, wrapped to the width the window gives it.
struct TomatoGardenView: View {

  // MARK: Internal

  static let glyphWidth: CGFloat = 20
  static let blockGap: CGFloat = 12

  let garden: TomatoGarden

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: Self.blockGap) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, block in
            HStack(spacing: 0) {
              ForEach(Array(block.enumerated()), id: \.offset) { _, filled in
                Text("🍅")
                  .font(.system(size: 16))
                  .opacity(filled ? 1 : 0.35)
                  .frame(width: Self.glyphWidth)
              }
            }
          }
        }
      }
      Text(garden.summary).font(.caption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(garden.summary)
    .background(
      GeometryReader { proxy in
        Color.clear
          .onAppear { width = proxy.size.width }
          .onChange(of: proxy.size.width) { _, new in width = new }
      }
    )
  }

  // MARK: Private

  @State private var width: CGFloat = 320

  private var rows: [[[Bool]]] {
    TomatoGarden.rows(
      of: garden.blocks,
      width: width,
      every: garden.blocks.first?.count ?? 1,
      glyphWidth: Self.glyphWidth,
      blockGap: Self.blockGap,
    )
  }

}

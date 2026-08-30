import SwiftUI

/// Flows subviews into centred rows: as many per row as fit the proposed width, never fewer than
/// one, `rowSpacing` between rows and `blockGap` between subviews. Each subview keeps its natural
/// size, so this serves both the garden's equal tomato blocks and the command chips' varied widths.
struct BlockFlowLayout: Layout {

  // MARK: Internal

  let blockGap: CGFloat
  let rowSpacing: CGFloat

  /// Greedy word-wrap over the known widths: as many indices per row as fit `available`, never
  /// fewer than one. The pure arithmetic behind `rows(for:)`, kept free of `Subviews` so it can
  /// be tested directly.
  static func rowBreaks(widths: [CGFloat], available: CGFloat, gap: CGFloat) -> [[Int]] {
    var rows: [[Int]] = [[]]
    var rowWidth: CGFloat = 0
    for (index, width) in widths.enumerated() {
      let leadingGap = rows[rows.count - 1].isEmpty ? 0 : gap
      if !rows[rows.count - 1].isEmpty, rowWidth + leadingGap + width > available {
        rows.append([])
        rowWidth = 0
      }
      rows[rows.count - 1].append(index)
      rowWidth += (rows[rows.count - 1].count == 1 ? 0 : gap) + width
    }
    return rows
  }

  /// The x-coordinate a row of `rowWidth` starts at to sit centred in `bounds`.
  static func rowOrigin(bounds: CGRect, rowWidth: CGFloat) -> CGFloat {
    bounds.minX + (bounds.width - rowWidth) / 2
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let rows = rows(for: subviews, width: width)
    let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
    let widest = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? widest, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
    var y = bounds.minY
    for row in rows(for: subviews, width: bounds.width) {
      var x = Self.rowOrigin(bounds: bounds, rowWidth: row.width)
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
        x += size.width + blockGap
      }
      y += row.height + rowSpacing
    }
  }

  // MARK: Private

  private struct Row {
    var indices = [Int]()
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  /// Greedy word-wrap over the subviews' natural sizes.
  private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let breaks = Self.rowBreaks(widths: sizes.map(\.width), available: width, gap: blockGap)
    return breaks.map { indices in
      Row(
        indices: indices,
        width: indices.enumerated().reduce(0) { total, pair in
          total + (pair.offset == 0 ? 0 : blockGap) + sizes[pair.element].width
        },
        height: indices.map { sizes[$0].height }.max() ?? 0,
      )
    }
  }

}

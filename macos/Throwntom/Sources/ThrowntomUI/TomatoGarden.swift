import Foundation

/// Today's pomodoros as blocks of tomatoes: one block per `long_break_every`, the current block
/// padded with dim slots so progress toward the long break is visible.
struct TomatoGarden: Equatable {

  // MARK: Lifecycle

  init(completedToday: Int, inBlock: Int, every: Int) {
    let every = max(every, 1)
    let completed = max(completedToday, 0)
    let partial = min(max(inBlock, 0), every - 1, completed)
    let whole = completed - partial
    var blocks = stride(from: 0, to: whole, by: every).map { start in
      Array(repeating: true, count: min(every, whole - start))
    }
    if partial > 0 {
      blocks.append(Array(repeating: true, count: partial) + Array(repeating: false, count: every - partial))
    } else if completed == 0 {
      blocks.append(Array(repeating: false, count: every))
    }
    self.blocks = blocks
    let done = completed / every
    summary = "\(completed) today · \(done) \(done == 1 ? "block" : "blocks") done"
  }

  // MARK: Internal

  let blocks: [[Bool]]
  let summary: String

  /// Blocks flowed like words: as many per row as fit in `width`, never fewer than one.
  static func rows(
    of blocks: [[Bool]],
    width: CGFloat,
    every: Int,
    glyphWidth: CGFloat = 20,
    blockGap: CGFloat = 12,
  ) -> [[[Bool]]] {
    let blockWidth = CGFloat(max(every, 1)) * glyphWidth
    let perRow = max(1, Int((width + blockGap) / (blockWidth + blockGap)))
    return stride(from: 0, to: blocks.count, by: perRow).map { Array(blocks[$0 ..< min($0 + perRow, blocks.count)]) }
  }

}

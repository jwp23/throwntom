import Foundation

/// Today's pomodoros as blocks of tomatoes: one block per `long_break_every`, the current block
/// padded with dim slots so progress toward the long break is visible.
struct TomatoGarden: Equatable {

  // MARK: Lifecycle

  init(completedToday: Int, inBlock: Int, every: Int) {
    let every = max(every, 1)
    let completed = max(completedToday, 0)
    // The daemon's work_sessions_in_block is cumulative and only wraps on
    // StartNewCycle or day-rollover (internal/engine/engine.go), so past the
    // first cycle it can exceed `every`. Reduce it mod `every` rather than
    // clamping to `every - 1`, or the block split degrades as the day's
    // total grows (GH #161).
    let partial = min(max(inBlock, 0) % every, completed)
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

}

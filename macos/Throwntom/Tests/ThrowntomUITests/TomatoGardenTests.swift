import XCTest
@testable import ThrowntomUI

final class TomatoGardenTests: XCTestCase {
  func testEmptyDayShowsOneDimBlock() {
    let g = TomatoGarden(completedToday: 0, inBlock: 0, every: 4)
    XCTAssertEqual(g.blocks, [[false, false, false, false]])
    XCTAssertEqual(g.summary, "0 today · 0 blocks done")
  }

  func testThreeIntoFourDimsTheRest() {
    let g = TomatoGarden(completedToday: 3, inBlock: 3, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, false]])
    XCTAssertEqual(g.summary, "3 today · 0 blocks done")
  }

  func testFullBlockHasNoDimSlots() {
    let g = TomatoGarden(completedToday: 4, inBlock: 0, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, true]])
    XCTAssertEqual(g.summary, "4 today · 1 block done")
  }

  func testElevenIsTwoBlocksAndAPartial() {
    let g = TomatoGarden(completedToday: 11, inBlock: 3, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, true], [true, true, true, true], [true, true, true, false]])
    XCTAssertEqual(g.summary, "11 today · 2 blocks done")
  }

  func testTwentyThreeWithEveryThree() {
    let g = TomatoGarden(completedToday: 23, inBlock: 2, every: 3)
    XCTAssertEqual(g.blocks.count, 8)
    XCTAssertEqual(g.blocks.last, [true, true, false])
    XCTAssertEqual(g.summary, "23 today · 7 blocks done")
  }

  func testInBlockIsClampedToWhatExists() {
    XCTAssertEqual(TomatoGarden(completedToday: 1, inBlock: 3, every: 4).blocks, [[true, false, false, false]])
  }

  func testEveryBelowOneBehavesAsOne() {
    XCTAssertEqual(TomatoGarden(completedToday: 2, inBlock: 0, every: 0).blocks, [[true], [true]])
  }

  /// The daemon's work_sessions_in_block never wraps after a natural long break
  /// (only StartNewCycle/day-rollover reset it — internal/engine/engine.go), so
  /// it reports the same cumulative total as completedToday. TomatoGarden must
  /// reduce that raw count mod `every`, not clamp it to `every - 1`, or the
  /// block split degrades as the day's total grows past one cycle. GH #161.
  func testFourInOneCycleIsASingleFullBlock() {
    let g = TomatoGarden(completedToday: 4, inBlock: 4, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, true]])
  }

  func testFiveWithCumulativeInBlockGroupsInFours() {
    let g = TomatoGarden(completedToday: 5, inBlock: 5, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, true], [true, false, false, false]])
  }

  func testSevenWithCumulativeInBlockGroupsInFours() {
    let g = TomatoGarden(completedToday: 7, inBlock: 7, every: 4)
    XCTAssertEqual(g.blocks, [[true, true, true, true], [true, true, true, false]])
  }

  func testInBlockPastAFullCycleIsReducedModEvery() {
    XCTAssertEqual(TomatoGarden(completedToday: 2, inBlock: 4, every: 4).blocks, [[true, true]])
  }
}

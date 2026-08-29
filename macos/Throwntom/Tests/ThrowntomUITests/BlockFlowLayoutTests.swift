import XCTest
@testable import ThrowntomUI

final class BlockFlowLayoutTests: XCTestCase {
  func testAllBlocksFitOnOneRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 400, gap: 12), [[0, 1, 2]])
  }

  func testTwoBlocksFitAndTheThirdWraps() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 180, gap: 12), [[0, 1], [2]])
  }

  func testOnlyOneBlockFitsPerRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 100, gap: 12), [[0], [1], [2]])
  }

  func testNeverFewerThanOnePerRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 10, gap: 12), [[0], [1], [2]])
  }

  func testRowOriginCentresANarrowRow() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
    XCTAssertEqual(BlockFlowLayout.rowOrigin(bounds: bounds, rowWidth: 100), 150)
  }

  func testRowOriginLeavesAFullWidthRowAtTheEdge() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
    XCTAssertEqual(BlockFlowLayout.rowOrigin(bounds: bounds, rowWidth: 400), 0)
  }
}

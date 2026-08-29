import SwiftUI
import XCTest
@testable import ThrowntomUI

final class TomatoBodyViewTests: XCTestCase {

  // MARK: Internal

  func testBodyIsACircleAtTheDesignCentre() {
    let bounds = TomatoBody.outline.path(in: canvas).boundingRect
    XCTAssertEqual(bounds, CGRect(x: 16, y: 22, width: 68, height: 68))
  }

  func testLeavesAndStemSitInTheTopBand() {
    let leaves = TomatoBody.leaves.path(in: canvas).boundingRect
    XCTAssertGreaterThanOrEqual(leaves.minY, 8)
    XCTAssertLessThanOrEqual(leaves.maxY, 24.5)
    XCTAssertEqual(leaves.midX, 50, accuracy: 1)
    let stem = TomatoBody.stem.path(in: canvas).boundingRect
    XCTAssertLessThan(stem.minY, leaves.minY + 2)
  }

  @MainActor
  func testBodyBuilds() {
    _ = TomatoBodyView(unit: 2).body
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

import SwiftUI
import XCTest
@testable import ThrowntomUI

final class FurnitureViewTests: XCTestCase {

  // MARK: Internal

  func testLaptopStandsOnTheRightWithItsScreenLeaningLeft() {
    let base = FurnitureShapes.laptopBase.path(in: canvas).boundingRect
    let screen = FurnitureShapes.laptopScreen.path(in: canvas).boundingRect
    XCTAssertEqual(base, CGRect(x: 60, y: 92, width: 36, height: 4))
    XCTAssertLessThan(screen.minY, 60)
    XCTAssertLessThan(screen.minX, base.maxX)
  }

  func testSofaSpansTheCanvasBottom() {
    let back = FurnitureShapes.sofaBack.path(in: canvas).boundingRect
    let seat = FurnitureShapes.sofaSeat.path(in: canvas).boundingRect
    let arms = FurnitureShapes.sofaArms.path(in: canvas).boundingRect
    XCTAssertEqual(seat, CGRect(x: 16, y: 72, width: 68, height: 18))
    XCTAssertLessThan(back.minY, seat.minY)
    XCTAssertEqual(arms.minX, 6)
    XCTAssertEqual(arms.maxX, 94)
  }

  @MainActor
  func testFurnitureBuilds() {
    _ = FurnitureView(furniture: .laptop, scheme: Palette.scheme(for: .work), unit: 2).body
    _ = FurnitureView(furniture: .sofa, scheme: Palette.scheme(for: .longBreak), unit: 2).body
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

import SwiftUI
import XCTest
@testable import ThrowntomUI

final class ArmShapeTests: XCTestCase {

  // MARK: Internal

  func testArmRunsFromShoulderToHand() {
    let arm = Arm(22, 70, 16, 80, 22, 86, 35, 85)
    let path = ArmShape(arm: arm).path(in: canvas)
    XCTAssertEqual(path.currentPoint, CGPoint(x: 35, y: 85))
    XCTAssertLessThan(path.boundingRect.minX, 22)
  }

  func testArmInterpolatesHalfway() {
    var shape = ArmShape(arm: Arm(0, 0, 0, 0, 0, 0, 0, 0))
    var halfway = ArmShape(arm: Arm(10, 20, 30, 40, 50, 60, 70, 80)).animatableData
    halfway.scale(by: 0.5)
    shape.animatableData = halfway
    XCTAssertEqual(shape.arm, Arm(5, 10, 15, 20, 25, 30, 35, 40))
  }

  func testHandIsADiscOfRadiusFourAtTheArmEnd() {
    let bounds = HandShape(centre: CGPoint(35, 85)).path(in: canvas).boundingRect
    XCTAssertEqual(bounds, CGRect(x: 31, y: 81, width: 8, height: 8))
  }

  @MainActor
  func testArmsBuild() {
    _ = ArmsView(left: Arm(22, 70, 16, 80, 22, 86, 35, 85), right: Arm(78, 70, 84, 80, 78, 86, 65, 85), unit: 2).body
    _ = HandsView(left: Arm(22, 70, 16, 80, 22, 86, 35, 85), right: Arm(78, 70, 84, 80, 78, 86, 65, 85), unit: 2).body
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

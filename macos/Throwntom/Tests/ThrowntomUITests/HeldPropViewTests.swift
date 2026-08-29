import SwiftUI
import XCTest
@testable import ThrowntomUI

final class HeldPropViewTests: XCTestCase {

  // MARK: Internal

  func testDrinkSitsInTheRightHand() {
    let cup = HeldProps.drinkCup.path(in: canvas).boundingRect
    XCTAssertEqual(cup, CGRect(x: 64, y: 70, width: 14, height: 22))
    XCTAssertLessThan(HeldProps.drinkStraw.path(in: canvas).boundingRect.minY, cup.minY)
  }

  func testBookCoversMeetAtTheSpineAndRecede() {
    let left = HeldProps.bookLeftCover.path(in: canvas).boundingRect
    let right = HeldProps.bookRightCover.path(in: canvas).boundingRect
    XCTAssertEqual(left.maxX, 50)
    XCTAssertEqual(right.minX, 50)
    XCTAssertEqual(left.maxY, 104)
    XCTAssertLessThan(HeldProps.bookPages.path(in: canvas).boundingRect.maxY, left.minY + 8)
  }

  func testYoyoDiscHangsBelowTheHandByTheDrop() {
    let near = HeldProps.yoyoDisc(drop: 4).path(in: canvas).boundingRect
    let far = HeldProps.yoyoDisc(drop: 18).path(in: canvas).boundingRect
    XCTAssertGreaterThan(far.midY, near.midY + 12)
    XCTAssertLessThan(far.midX, near.midX)
    XCTAssertEqual(HeldProps.yoyoString(drop: 18).path(in: canvas).currentPoint?.y ?? 0, far.midY, accuracy: 8)
  }

  func testCableEndsLeaveBothHands() {
    XCTAssertEqual(HeldProps.cableLeft.path(in: canvas).boundingRect.minX, 35, accuracy: 1)
    XCTAssertEqual(HeldProps.cableRight.path(in: canvas).boundingRect.maxX, 94, accuracy: 1)
  }

  @MainActor
  func testEveryPropBuilds() {
    for prop in [HeldProp.drink, .book, .yoyo, .cable, .exclamation] {
      _ = HeldPropView(prop: prop, yoyoDrop: 10, unit: 2).body
    }
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

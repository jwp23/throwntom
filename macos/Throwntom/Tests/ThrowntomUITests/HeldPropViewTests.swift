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

  func testYoyoGrooveSpansTheDisc() {
    let groove = HeldProps.yoyoGroove(drop: 10).path(in: canvas).boundingRect
    let disc = HeldProps.yoyoDisc(drop: 10).path(in: canvas).boundingRect
    XCTAssertEqual(groove.width, 2 * 0.978 * HeldProps.yoyoDiscRadius, accuracy: 0.1)
    XCTAssertEqual(groove.midX, disc.midX, accuracy: 0.1)
    XCTAssertEqual(groove.midY, disc.midY, accuracy: 0.1)
  }

  func testCableEndsLeaveBothHands() {
    XCTAssertEqual(HeldProps.cableLeft.path(in: canvas).boundingRect.minX, 35, accuracy: 1)
    XCTAssertEqual(HeldProps.cableRight.path(in: canvas).boundingRect.maxX, 88, accuracy: 1)
    XCTAssertEqual(HeldProps.cablePlug.path(in: canvas).boundingRect.maxX, 56)
    XCTAssertEqual(HeldProps.cableProngs.path(in: canvas).boundingRect.maxX, 60)
    XCTAssertEqual(HeldProps.cableSocket.path(in: canvas).boundingRect.minX, 88)
  }

  /// The cap is a cone standing on its own brim, so the two share an edge; the bobble hangs off
  /// the far side, which is what makes the point read as flopped over rather than upright.
  func testTheNightcapConeStandsOnItsBrimWithTheBobbleAtItsPoint() {
    let cone = HeldProps.nightcapCone.path(in: canvas).boundingRect
    let brim = HeldProps.nightcapBrim.path(in: canvas).boundingRect
    let bobble = HeldProps.nightcapBobble.path(in: canvas).boundingRect

    XCTAssertEqual(brim.maxY, cone.maxY, accuracy: 1, "the brim runs along the bottom of the cap")
    XCTAssertLessThan(cone.minY, brim.minY, "the cap rises above its own brim")
    XCTAssertLessThan(bobble.midX, brim.minX, "the point flops off the far side")
    XCTAssertEqual(bobble.midY, cone.minY, accuracy: 4, "and the bobble is at that point, not adrift")
  }

  /// The tomato has to stay a tomato in a hat. Its stem and both leaves live above y 24, so a cap
  /// drawn over them leaves a red ball with a face on it — which is the whole of what the crown
  /// does for the character.
  func testTheNightcapLeavesTheStemAndLeavesShowing() {
    let cap = HeldProps.nightcapCone.path(in: canvas)
    for crown in [CGPoint(x: 43, y: 20), CGPoint(x: 57, y: 20), CGPoint(x: 52, y: 14)] {
      XCTAssertFalse(cap.contains(crown), "the cap covers the crown at \(crown)")
    }
  }

  /// Three Z's on one cycle, staggered by thirds, so the still frame Reduce Motion draws — and the
  /// snapshot renderer with it — is a small-to-large `zZZ` rather than three of the same size.
  func testTheZsStandStaggeredSmallToLargeInAStillFrame() {
    let widths = (0 ..< HeldProps.zedCount).map {
      HeldProps.zed(progress: HeldProps.zedProgress($0, phase: 0)).path(in: canvas).boundingRect.width
    }

    XCTAssertEqual(widths.count, 3)
    XCTAssertLessThan(widths[0], widths[1])
    XCTAssertLessThan(widths[1], widths[2])
  }

  /// They rise away from the head over the cycle, and the cycle closes on itself: the Z that leaves
  /// the top is the same one that comes back at the bottom.
  func testAZDriftsUpAndAwayAndReturnsWhereItStarted() {
    let start = HeldProps.zed(progress: 0).path(in: canvas).boundingRect
    let later = HeldProps.zed(progress: 0.5).path(in: canvas).boundingRect

    XCTAssertLessThan(later.midY, start.midY, "up")
    XCTAssertGreaterThan(later.midX, start.midX, "and away from the face")
    XCTAssertEqual(HeldProps.zedProgress(0, phase: 1), HeldProps.zedProgress(0, phase: 0), accuracy: 0.001)
  }

  /// A Z dissolves at the top of its cycle instead of blinking off there. It is fully painted at
  /// the bottom, which is what keeps three of them on screen in a still frame.
  func testAZFadesOnlyAsItLeaves() {
    XCTAssertEqual(HeldProps.zedOpacity(progress: 0), 1)
    XCTAssertEqual(HeldProps.zedOpacity(progress: 2.0 / 3), 1)
    XCTAssertEqual(HeldProps.zedOpacity(progress: 1), 0)
    XCTAssertLessThan(HeldProps.zedOpacity(progress: 0.9), 1)
  }

  @MainActor
  func testEveryPropBuilds() {
    for prop in [HeldProp.drink, .book, .yoyo, .cable, .exclamation, .burger, .nightcap] {
      _ = HeldPropView(prop: prop, yoyoDrop: 10, zzzPhase: 0.25, unit: 2).body
    }
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

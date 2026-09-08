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

  /// The cap is a cone standing on its own brim, so the two share an edge; the cone flops toward
  /// the near side, into the long thin point of the approved mock, whose bobble hangs off the
  /// head's edge past it (mock: bobble at (87, 14)).
  func testTheNightcapConeStandsOnItsBrimWithTheBobbleAtItsPoint() {
    let cone = HeldProps.nightcapCone.path(in: canvas).boundingRect
    let brim = HeldProps.nightcapBrim.path(in: canvas).boundingRect
    let bobble = HeldProps.nightcapBobble.path(in: canvas).boundingRect

    XCTAssertEqual(brim.maxY, cone.maxY, accuracy: 1, "the brim runs along the bottom of the cap")
    XCTAssertLessThan(cone.minY, brim.minY, "the cap rises above its own brim")
    XCTAssertGreaterThan(bobble.midX, brim.maxX, "the point flops off the near side")
    XCTAssertGreaterThan(bobble.midX, 85, "the bobble hangs off the head's edge, past the point")
    XCTAssertGreaterThan(bobble.maxX, cone.maxX, "the bobble hangs past the tip")
    XCTAssertLessThan(bobble.midY, 16, "and stays up on the crown, not adrift down the face")
  }

  /// The cap sits where the crown was: it spans the head's top and its point's finger reaches out
  /// toward the bobble, so the bare crown never shows around it. The stem and leaves themselves
  /// are not drawn while it is worn — the asleep pose is not `crowned` — and `MascotSnapshotTests`
  /// proves no leaf green survives. Points follow the approved mock (throwntom-bxd.5).
  func testTheNightcapSpansTheCrown() {
    let cap = HeldProps.nightcapCone.path(in: canvas)
    let inside = [
      CGPoint(x: 40, y: 22),
      CGPoint(x: 50, y: 18),
      CGPoint(x: 60, y: 16),
      CGPoint(x: 35, y: 26),
      CGPoint(x: 80, y: 13), // the thin finger, on its way to the bobble
    ]
    for point in inside {
      XCTAssertTrue(cap.contains(point), "the cap misses the crown at \(point)")
    }
  }

  /// The cap belongs to the top of the head: its brim rides the crown, well clear of the face.
  func testTheNightcapStaysAboveTheFace() {
    XCTAssertLessThanOrEqual(HeldProps.nightcapCone.path(in: canvas).boundingRect.maxY, 34)
  }

  /// The cap is not a pillow: past its crest the silhouette is pared down to a thin finger, so
  /// there is cream neither above the crest, above the finger, nor sagging under it.
  func testTheNightcapTapersThinPastTheCrest() {
    let cap = HeldProps.nightcapCone.path(in: canvas)
    for outside in [CGPoint(x: 52, y: 3), CGPoint(x: 80, y: 8), CGPoint(x: 78, y: 19)] {
      XCTAssertFalse(cap.contains(outside), "the cap is fat at \(outside)")
    }
  }

  /// The Z's sit exactly where the approved mock drew them: the smallest sets off beside the cheek
  /// at (78, 44) and the run ends in the corner at (93.5, 15.5), growing from 4 to 8.5 across.
  func testTheZsFollowTheMocksRun() {
    XCTAssertEqual(HeldProps.zed(progress: 0).path(in: canvas).boundingRect, CGRect(x: 76, y: 42, width: 4, height: 4))
    let top = HeldProps.zed(progress: 1).path(in: canvas).boundingRect
    XCTAssertEqual(top.midX, 93.5, accuracy: 0.01)
    XCTAssertEqual(top.midY, 15.5, accuracy: 0.01)
    XCTAssertEqual(top.width, 8.5, accuracy: 0.01)
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

  /// Three distinct Z's, not a pile: at no point in the cycle do two of them touch, even with
  /// their stroke width on.
  func testTheZsNeverTouch() {
    let strokeRadius = 0.8
    for phase in stride(from: 0.0, through: 1.0, by: 0.02) {
      let boxes = (0 ..< HeldProps.zedCount).compactMap { index -> CGRect? in
        let progress = HeldProps.zedProgress(index, phase: phase)
        guard HeldProps.zedOpacity(progress: progress) > 0 else { return nil }
        return HeldProps.zed(progress: progress).path(in: canvas)
          .boundingRect.insetBy(dx: -strokeRadius, dy: -strokeRadius)
      }
      for (index, box) in boxes.enumerated() {
        for other in boxes[(index + 1)...] {
          XCTAssertFalse(box.intersects(other), "Z's touch at phase \(phase)")
        }
      }
    }
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
      _ = HeldPropView(prop: prop, yoyoDrop: 10, unit: 2).body
    }
    _ = ZedsView(zzzPhase: 0.25, unit: 2).body
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

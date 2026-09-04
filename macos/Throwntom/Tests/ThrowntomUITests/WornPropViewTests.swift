import SwiftUI
import XCTest
@testable import ThrowntomUI

final class WornPropViewTests: XCTestCase {

  // MARK: Internal

  func testHeadsetBandArcsOverTheCrownBetweenBothCups() {
    let band = WornProps.headsetBand.path(in: canvas).boundingRect
    XCTAssertEqual(band.minX, 19, accuracy: 0.5)
    XCTAssertEqual(band.maxX, 81, accuracy: 0.5)
    // The crown of the body circle is y 22 and the leaves start at y 24, so the band rides the
    // head above the eyes (y 55) without cutting through the stem.
    XCTAssertLessThan(band.minY, 32)
    XCTAssertGreaterThan(band.minY, TomatoBody.centre.y - TomatoBody.radius)
    XCTAssertEqual(band.maxY, 45, accuracy: 0.5)
  }

  func testCupsStrandTheBodyRimSoTheSilhouetteBreaks() {
    let far = WornProps.headsetFarCup.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    // Body circle centre (50, 56) radius 34: both cups reach past the rim at their own height.
    XCTAssertLessThan(far.minX, TomatoBody.centre.x - rimHalfWidth(atY: far.midY))
    XCTAssertGreaterThan(near.maxX, TomatoBody.centre.x + rimHalfWidth(atY: near.midY))
    // The near side is the three-quarter face's near side, so its cup is the larger one.
    XCTAssertGreaterThan(near.width, far.width)
    XCTAssertGreaterThan(near.height, far.height)
    // Both cups sit at ear height, level with the eyes at y 54-55.
    XCTAssertLessThan(far.minY, 55)
    XCTAssertGreaterThan(far.maxY, 55)
    XCTAssertLessThan(near.minY, 55)
    XCTAssertGreaterThan(near.maxY, 55)
  }

  func testBandEndsInsideBothCups() {
    let band = WornProps.headsetBand.path(in: canvas).boundingRect
    let far = WornProps.headsetFarCup.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    XCTAssertGreaterThanOrEqual(band.maxY, far.minY)
    XCTAssertGreaterThanOrEqual(band.maxY, near.minY)
    XCTAssertLessThan(abs(band.minX - far.midX), far.width / 2)
    XCTAssertLessThan(abs(band.maxX - near.midX), near.width / 2)
  }

  func testBoomReachesFromTheNearCupToTheMouthWithoutCoveringIt() {
    let boom = WornProps.headsetBoom.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    let mic = WornProps.headsetMic.path(in: canvas).boundingRect
    let mouth = TomatoFace.mouthShape(.smile).path(in: canvas).boundingRect
    // It leaves the near cup and travels forward and down.
    XCTAssertLessThan(boom.maxX, near.maxX)
    XCTAssertGreaterThan(boom.maxY, near.maxY)
    // The capsule lands beside the mouth's near corner, clear of the mouth itself.
    XCTAssertGreaterThan(mic.minX, mouth.maxX)
    XCTAssertLessThan(mic.minX, mouth.maxX + 4)
    XCTAssertEqual(mic.midX, boom.minX, accuracy: 3)
    XCTAssertEqual(mic.midY, boom.maxY, accuracy: 3)
  }

  func testCupPlateSitsInsideTheNearCup() {
    let plate = WornProps.headsetNearCupPlate.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    XCTAssertTrue(near.insetBy(dx: 1, dy: 1).contains(plate))
  }

  @MainActor
  func testEveryWornPropBuilds() {
    for prop in WornProp.allCases {
      for unit in [CGFloat(1), 2, 3.2] {
        _ = WornPropView(prop: prop, unit: unit).body
      }
    }
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

  /// How far the body circle reaches either side of its centre at the given height.
  private func rimHalfWidth(atY y: CGFloat) -> CGFloat {
    let dy = Double(y) - Double(TomatoBody.centre.y)
    return CGFloat((TomatoBody.radius * TomatoBody.radius - dy * dy).squareRoot())
  }

}

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

  func testBoomReachesFromTheNearCupDownTowardTheJaw() {
    let boom = WornProps.headsetBoom.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    let mic = WornProps.headsetMic.path(in: canvas).boundingRect
    // It leaves the near cup and travels down and forward.
    XCTAssertGreaterThan(boom.maxY, near.maxY)
    XCTAssertGreaterThan(mic.midY, near.maxY)
    XCTAssertEqual(mic.midX, boom.minX, accuracy: 3)
    XCTAssertEqual(mic.midY, boom.maxY, accuracy: 3)
  }

  /// The capsule has to read as a microphone, which means being seen as its own object. Two
  /// things take that away: the mouth, which it merges with when held against the smile's near
  /// corner, and the body's own outline at the rim, where a dark capsule disappears into the
  /// stroke it is sitting on. It belongs in the open cheek between the two, clear of both.
  ///
  /// The pocket is only about fourteen units wide, so a capsule of any useful size cannot be far
  /// from both edges — which is why colour does the rest of the work (see
  /// `testTheMicIsPaintedAsHardwareRatherThanAsAnOutline`). The gap here is the most the
  /// geometry affords, not a target chosen freely.
  ///
  /// Measured against the mouth the meeting pose actually wears rather than one named here, so
  /// re-drawing that pose's face is what moves the goalposts, not an edit to this line.
  func testTheMicSitsInTheOpenCheekBetweenTheMouthAndTheRim() {
    let mic = WornProps.headsetMic.path(in: canvas).boundingRect
    let mouth = TomatoFace.mouthShape(MascotPose.meeting.mouth).path(in: canvas).boundingRect
    let rim = TomatoBody.centre.x + rimHalfWidth(atY: mic.midY)

    XCTAssertGreaterThan(mic.minX - mouth.maxX, 4, "the capsule is crowding the mouth")
    XCTAssertLessThan(mic.maxX, rim - 2, "the capsule is sitting on the body outline")
  }

  /// A pair of ears is a pair: two cups painted differently read as a mistake rather than as
  /// perspective, so each carries the same pad in the same colours, sized to its own cup.
  func testBothCupsCarryAPadSizedToThatCup() {
    let cups = [
      (cup: WornProps.headsetFarCup, pad: WornProps.headsetFarCupPad),
      (cup: WornProps.headsetNearCup, pad: WornProps.headsetNearCupPad),
    ]
    for (cup, pad) in cups {
      let cupRect = cup.path(in: canvas).boundingRect
      let padRect = pad.path(in: canvas).boundingRect
      XCTAssertTrue(cupRect.insetBy(dx: 1, dy: 1).contains(padRect))
      XCTAssertEqual(padRect.midX, cupRect.midX, accuracy: 0.5)
      XCTAssertEqual(padRect.midY, cupRect.midY, accuracy: 0.5)
    }
    // Sized to its own cup, so the pair reads as the same object seen from two angles.
    let far = WornProps.headsetFarCup.path(in: canvas).boundingRect
    let near = WornProps.headsetNearCup.path(in: canvas).boundingRect
    let farPad = WornProps.headsetFarCupPad.path(in: canvas).boundingRect
    let nearPad = WornProps.headsetNearCupPad.path(in: canvas).boundingRect
    XCTAssertEqual(farPad.width / far.width, nearPad.width / near.width, accuracy: 0.1)
  }

  /// The capsule wears the cups' own shell colour rather than the dark of the band. A dark blob
  /// against the body's outline is the thing that stopped it reading as a microphone at all; a
  /// light one on the red cheek is unmistakably a piece of the same hardware as the ears.
  @MainActor
  func testTheMicIsPaintedAsHardwareRatherThanAsAnOutline() throws {
    let ground = Palette.scheme(for: .meeting)
    let appearance = try XCTUnwrap(AppearanceRender.appearances.first)
    let drawn = try AppearanceRender.bitmap(
      AppearanceRender.onGround(WornPropView(prop: .headset, unit: 4), scheme: ground, width: 400, height: 400),
      appearance: appearance.appearance,
      scheme: appearance.scheme,
    )
    let shell = try AppearanceRender.swatch(
      MascotPalette.propLight,
      appearance: appearance.appearance,
      scheme: appearance.scheme,
    )

    // Two cups and the capsule, so the shell colour has to cover appreciably more than the cups
    // alone would: the capsule is the third light object on the ground.
    XCTAssertGreaterThan(AppearanceRender.pixels(of: shell, in: drawn), 500)
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

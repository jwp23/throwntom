import SwiftUI
import XCTest
@testable import ThrowntomUI

final class TomatoFaceViewTests: XCTestCase {

  // MARK: Internal

  func testEyesSitOnTheNearSideOfTheFace() {
    let openBounds = TomatoFace.eyeOutline(.open).path(in: canvas).boundingRect
    XCTAssertGreaterThan(openBounds.midX, 50, "open shifted right")
    XCTAssertEqual(openBounds.midY, 54.5, accuracy: 1, "open on the eye line")

    let closedBounds = TomatoFace.eyeOutline(.closed).path(in: canvas).boundingRect
    XCTAssertGreaterThan(closedBounds.midX, 50, "closed shifted right")
    XCTAssertEqual(closedBounds.midY, 55.5, accuracy: 1, "closed on the eye line")

    let downBounds = TomatoFace.eyeOutline(.down).path(in: canvas).boundingRect
    XCTAssertGreaterThan(downBounds.midX, 50, "down shifted right")
    XCTAssertEqual(downBounds.midY, 55.5, accuracy: 1, "down on the eye line")

    let wideBounds = TomatoFace.eyeOutline(.wide).path(in: canvas).boundingRect
    XCTAssertGreaterThan(wideBounds.midX, 50, "wide shifted right")
    XCTAssertEqual(wideBounds.midY, 54.5, accuracy: 1, "wide on the eye line")
  }

  func testWideEyesAreBiggerThanOpenEyes() {
    let open = TomatoFace.eyeOutline(.open).path(in: canvas).boundingRect
    let wide = TomatoFace.eyeOutline(.wide).path(in: canvas).boundingRect
    XCTAssertGreaterThan(wide.height, open.height)
  }

  func testMouthsSitBelowTheEyes() {
    for mouth in [Mouth.smile, .open, .flat, .grin] {
      let bounds = TomatoFace.mouthShape(mouth).path(in: canvas).boundingRect
      XCTAssertGreaterThan(bounds.minY, 60, "\(mouth)")
      XCTAssertEqual(bounds.midX, 58, accuracy: 2, "\(mouth)")
    }
  }

  @MainActor
  func testFaceBuildsForEveryVariant() {
    for eyes in [Eyes.open, .closed, .down, .wide] {
      for mouth in [Mouth.smile, .open, .flat, .grin] {
        _ = TomatoFaceView(eyes: eyes, mouth: mouth, unit: 2).body
      }
    }
  }

  // MARK: Private

  private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

}

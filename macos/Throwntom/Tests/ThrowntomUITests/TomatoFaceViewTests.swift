import SwiftUI
import XCTest
@testable import ThrowntomUI

final class TomatoFaceViewTests: XCTestCase {

  // MARK: Internal

  func testEyesSitOnTheNearSideOfTheFace() {
    for eyes in [Eyes.open, .closed, .down, .wide] {
      let bounds = TomatoFace.eyeOutline(eyes).path(in: canvas).boundingRect
      XCTAssertGreaterThan(bounds.midX, 50, "\(eyes) shifted right")
      XCTAssertEqual(bounds.midY, 55, accuracy: 3, "\(eyes) on the eye line")
    }
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

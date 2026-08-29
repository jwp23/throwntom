import SwiftUI
import XCTest
@testable import ThrowntomUI

@MainActor
final class MascotViewTests: XCTestCase {
  func testBlinkClosesOpenEyesOnly() {
    let blink = MotionFrame(bobDegrees: 0, blinking: true, yoyoDrop: 4, jumpLift: 0)
    XCTAssertEqual(MascotCharacterView.eyes(for: .work, frame: blink), .closed)
    XCTAssertEqual(MascotCharacterView.eyes(for: .work, frame: .still), .open)
    XCTAssertEqual(MascotCharacterView.eyes(for: .awaitingConfirm, frame: blink), .wide)
    XCTAssertEqual(MascotCharacterView.eyes(for: .idle, frame: blink), .down)
  }

  func testEveryPoseBuildsAtEveryScale() {
    let poses: [MascotPose] = [.work, .shortBreak, .longBreak, .idle, .awaitingConfirm, .disconnected, MascotPose.work.paused()]
    for pose in poses {
      for unit in [CGFloat(1), 2, 3.2] {
        _ = MascotCharacterView(
          pose: pose,
          frame: .still,
          scheme: Palette.scheme(for: .work),
          unit: unit,
          animatesPoseChanges: true,
        ).body
      }
      _ = MascotView(pose: pose, scheme: Palette.scheme(for: .longBreak)).body
    }
  }

  func testLayerOrderIsCorrect() {
    XCTAssertEqual(MascotCharacterView.layers(for: .longBreak), [.body, .face, .arms, .held(.book), .hands])
    XCTAssertEqual(MascotCharacterView.layers(for: .shortBreak), [.body, .face, .arms, .hands, .held(.drink)])
    XCTAssertEqual(MascotCharacterView.layers(for: .work), [.body, .face, .arms, .hands])
  }

  func testPoseChangesDoNotAnimateUnderReduceMotion() {
    _ = MascotCharacterView(pose: .work, frame: .still, scheme: Palette.scheme(for: .work), unit: 2, animatesPoseChanges: false)
      .body
  }

  func testLayersAreUniqueSoIdentityIsStable() {
    let poses: [MascotPose] = [.work, .shortBreak, .longBreak, .idle, .awaitingConfirm, .disconnected]
    for pose in poses {
      let layers = MascotCharacterView.layers(for: pose)
      XCTAssertEqual(Set(layers).count, layers.count)
    }
  }
}

import ThrowntomClient
import XCTest
@testable import ThrowntomUI

final class MascotPoseTests: XCTestCase {
  func testEveryPhaseHasItsOwnPose() {
    XCTAssertEqual(MascotPose.pose(for: .work, pausedFrom: .idle).furniture, .laptop)
    XCTAssertEqual(MascotPose.pose(for: .meeting, pausedFrom: .idle).worn, .headset)
    XCTAssertEqual(MascotPose.pose(for: .shortBreak, pausedFrom: .idle).held, .drink)
    XCTAssertEqual(MascotPose.pose(for: .longBreak, pausedFrom: .idle).held, .book)
    XCTAssertEqual(MascotPose.pose(for: .longBreak, pausedFrom: .idle).furniture, .sofa)
    XCTAssertEqual(MascotPose.pose(for: .idle, pausedFrom: .idle).held, .yoyo)
    XCTAssertEqual(MascotPose.pose(for: .awaitingConfirm, pausedFrom: .idle).eyes, .wide)
    XCTAssertEqual(MascotPose.pose(for: nil, pausedFrom: .idle).held, .cable)
  }

  func testPausedKeepsThePausedPhasesPoseWithEyesShutAndNoMotion() {
    let paused = MascotPose.pose(for: .paused, pausedFrom: .longBreak)
    XCTAssertEqual(paused.held, .book)
    XCTAssertEqual(paused.eyes, .closed)
    XCTAssertTrue(paused.motions.isEmpty)
    XCTAssertEqual(MascotPose.pose(for: .paused, pausedFrom: .work).furniture, .laptop)
    XCTAssertEqual(MascotPose.pose(for: .paused, pausedFrom: .idle).held, .yoyo)
    XCTAssertEqual(MascotPose.pose(for: .paused, pausedFrom: .meeting).worn, .headset)
  }

  /// The meeting phase takes work's ground, so the headset is the whole of what separates the two
  /// poses; everything else must stay the work pose or the difference stops reading as "still
  /// working, just in a call".
  func testMeetingIsTheWorkPoseInAHeadset() {
    XCTAssertNil(MascotPose.work.worn)
    XCTAssertEqual(MascotPose.meeting.worn, .headset)
    var withoutHeadset = MascotPose.meeting
    withoutHeadset.worn = nil
    XCTAssertEqual(withoutHeadset, MascotPose.work)
  }

  func testOnlyAwaitingConfirmJumpsAndOnlyIdlePlaysYoyo() {
    XCTAssertEqual(MascotPose.awaitingConfirm.motions, [.jump])
    XCTAssertTrue(MascotPose.idle.motions.contains(.yoyo))
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .disconnected] {
      XCTAssertFalse(pose.motions.contains(.jump))
      XCTAssertFalse(pose.motions.contains(.yoyo))
    }
  }

  func testClosedEyesNeverBlink() {
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .idle, .awaitingConfirm, .disconnected] {
      if pose.eyes != .open {
        XCTAssertFalse(pose.motions.contains(.blink), "\(pose.held.map { "\($0)" } ?? "laptop")")
      }
    }
  }

  func testSofaPoseShrinksTheTomatoToFitTheFurniture() {
    XCTAssertEqual(MascotPose.longBreak.scale, 0.8)
    XCTAssertEqual(MascotPose.work.scale, 1)
    XCTAssertTrue(HeldProp.book.drawnBehindHands)
    XCTAssertFalse(HeldProp.drink.drawnBehindHands)
  }

  func testEveryPoseHangsItsArmsFromTheSameShoulders() {
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .idle, .awaitingConfirm, .disconnected] {
      XCTAssertEqual(pose.leftArm.shoulder, MascotPose.leftShoulder, "\(pose.held.map { "\($0)" } ?? "laptop") left")
      XCTAssertEqual(pose.rightArm.shoulder, MascotPose.rightShoulder, "\(pose.held.map { "\($0)" } ?? "laptop") right")
    }
  }
}

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
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .asleep, .disconnected] {
      XCTAssertFalse(pose.motions.contains(.jump))
      XCTAssertFalse(pose.motions.contains(.yoyo))
    }
  }

  /// A snooze quiets everything, so the pose that means one is the pose that stops shouting: eyes
  /// shut, the `!` put down, and nothing left jumping. It is what the awaiting-confirm pose was
  /// asked to stand in for, and it said the opposite of what had just been asked for.
  func testTheAsleepPoseIsQuietWhereAwaitingConfirmIsLoud() {
    let asleep = MascotPose.asleep

    XCTAssertEqual(asleep.eyes, .closed)
    XCTAssertEqual(asleep.held, .nightcap)
    XCTAssertFalse(asleep.crowned, "the cap replaces the crown; drawing both leaks the swept leaf tip")
    XCTAssertEqual(asleep.motions, [.breathe, .zzz])
    XCTAssertEqual(MascotPose.awaitingConfirm.held, .exclamation, "the pose it replaces still holds the shout")
  }

  /// The arms come down with the eyes. Measured against the shoulders they hang from, so a repose
  /// cannot quietly put them back over the head where awaiting confirm keeps them.
  func testTheAsleepArmsFoldBelowTheShouldersRatherThanReachingOverThem() {
    XCTAssertGreaterThan(MascotPose.asleep.leftArm.hand.y, MascotPose.leftShoulder.y)
    XCTAssertGreaterThan(MascotPose.asleep.rightArm.hand.y, MascotPose.rightShoulder.y)
    XCTAssertLessThan(MascotPose.awaitingConfirm.leftArm.hand.y, MascotPose.leftShoulder.y)
    XCTAssertLessThan(MascotPose.awaitingConfirm.rightArm.hand.y, MascotPose.rightShoulder.y)
  }

  func testClosedEyesNeverBlink() {
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .idle, .awaitingConfirm, .asleep, .disconnected] {
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
    for pose in [MascotPose.work, .meeting, .shortBreak, .longBreak, .lunch, .idle, .awaitingConfirm, .asleep, .disconnected] {
      XCTAssertEqual(pose.leftArm.shoulder, MascotPose.leftShoulder, "\(pose.held.map { "\($0)" } ?? "laptop") left")
      XCTAssertEqual(pose.rightArm.shoulder, MascotPose.rightShoulder, "\(pose.held.map { "\($0)" } ?? "laptop") right")
    }
  }
}

import XCTest
@testable import ThrowntomUI

final class MascotMotionTests: XCTestCase {
  func testNoMotionsIsStill() {
    XCTAssertEqual(MascotMotion.frame(at: 1.7, motions: []), .still)
    XCTAssertEqual(MotionFrame.still.yoyoDrop, MascotMotion.yoyoDropRange.lowerBound)
    XCTAssertEqual(MotionFrame.still.zzzPhase, 0)
  }

  func testBreathingBobsWithinTwoDegrees() {
    let quarter = MascotMotion.frame(at: MascotMotion.breathePeriod / 4, motions: [.breathe])
    XCTAssertEqual(quarter.bobDegrees, MascotMotion.breatheDegrees, accuracy: 0.001)
    let threeQuarters = MascotMotion.frame(at: MascotMotion.breathePeriod * 3 / 4, motions: [.breathe])
    XCTAssertEqual(threeQuarters.bobDegrees, -MascotMotion.breatheDegrees, accuracy: 0.001)
    XCTAssertEqual(MascotMotion.frame(at: 1, motions: [.jump]).bobDegrees, 0)
  }

  func testBlinkIsBriefAndPeriodic() {
    XCTAssertFalse(MascotMotion.frame(at: 0, motions: [.blink]).blinking)
    XCTAssertFalse(MascotMotion.frame(at: 1, motions: [.blink]).blinking)
    XCTAssertTrue(MascotMotion.frame(at: MascotMotion.blinkInterval - 0.05, motions: [.blink]).blinking)
    XCTAssertFalse(MascotMotion.frame(at: MascotMotion.blinkInterval + 0.05, motions: [.blink]).blinking)
    XCTAssertTrue(MascotMotion.frame(at: 2 * MascotMotion.blinkInterval - 0.05, motions: [.blink]).blinking)
    XCTAssertFalse(MascotMotion.frame(at: MascotMotion.blinkInterval - 0.05, motions: [.breathe]).blinking)
  }

  func testYoyoDropsAndReturns() {
    let top = MascotMotion.frame(at: 0, motions: [.yoyo]).yoyoDrop
    let bottom = MascotMotion.frame(at: MascotMotion.yoyoPeriod / 2, motions: [.yoyo]).yoyoDrop
    XCTAssertEqual(top, MascotMotion.yoyoDropRange.lowerBound, accuracy: 0.001)
    XCTAssertEqual(bottom, MascotMotion.yoyoDropRange.upperBound, accuracy: 0.001)
  }

  /// The Z's carry one number, their place in the cycle; `HeldProps` turns it into three staggered
  /// Z's. It runs 0 to 1 and closes, so the Z leaving the top is the one arriving at the bottom.
  func testZzzRunsOnceThroughItsCycleAndCloses() {
    XCTAssertEqual(MascotMotion.frame(at: 0, motions: [.zzz]).zzzPhase, 0, accuracy: 0.001)
    XCTAssertEqual(MascotMotion.frame(at: MascotMotion.zzzPeriod / 2, motions: [.zzz]).zzzPhase, 0.5, accuracy: 0.001)
    XCTAssertEqual(MascotMotion.frame(at: MascotMotion.zzzPeriod, motions: [.zzz]).zzzPhase, 0, accuracy: 0.001)
    XCTAssertEqual(MascotMotion.frame(at: 1, motions: [.breathe]).zzzPhase, 0, "only .zzz drives it")
  }

  /// The Z's outlast the breath they drift over, so the two never fall into step and pulse as one.
  func testTheZzzCycleOutlastsABreath() {
    XCTAssertGreaterThan(MascotMotion.zzzPeriod, MascotMotion.breathePeriod)
  }

  func testJumpLiftsThenRests() {
    let peak = MascotMotion.frame(at: MascotMotion.jumpPeriod / 4, motions: [.jump]).jumpLift
    let landed = MascotMotion.frame(at: MascotMotion.jumpPeriod * 3 / 4, motions: [.jump]).jumpLift
    XCTAssertEqual(peak, MascotMotion.jumpLift, accuracy: 0.001)
    XCTAssertEqual(landed, 0)
  }
}

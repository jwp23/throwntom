import SwiftUI

// MARK: - MotionFrame

/// Where every moving part is at one instant.
struct MotionFrame: Equatable {
  static let still = MotionFrame(
    bobDegrees: 0,
    blinking: false,
    yoyoDrop: MascotMotion.yoyoDropRange.lowerBound,
    jumpLift: 0,
    zzzPhase: 0,
  )

  var bobDegrees: Double
  var blinking: Bool
  var yoyoDrop: Double
  var jumpLift: Double
  /// Where the Z's are in their cycle, 0 to 1. `HeldProps` turns the one number into three Z's
  /// staggered by thirds, so a still frame at 0 is a small-to-large `zZZ` rather than a blank.
  var zzzPhase: Double
}

// MARK: - MascotMotion

/// The mascot's idle motions as pure functions of elapsed time, so the view only samples a clock.
enum MascotMotion {
  static let blinkInterval: TimeInterval = 4
  static let blinkDuration: TimeInterval = 0.12
  static let breathePeriod: TimeInterval = 3
  static let breatheDegrees: Double = 2
  static let yoyoPeriod: TimeInterval = 1.2
  static let yoyoDropRange: ClosedRange<Double> = 4 ... 18
  static let jumpPeriod: TimeInterval = 1.2
  static let jumpLift: Double = 6
  /// Longer than a breath, so the two never fall into step and read as one pulse.
  static let zzzPeriod: TimeInterval = 4
  /// Arms and rotation bend into a new pose at the same pace the ground recolours.
  static let poseChange = Animation.easeOut(duration: 0.25)

  static func frame(at seconds: TimeInterval, motions: Set<Motion>) -> MotionFrame {
    var frame = MotionFrame.still
    if motions.contains(.breathe) {
      frame.bobDegrees = breatheDegrees * sin(2 * .pi * seconds / breathePeriod)
    }
    if motions.contains(.blink) {
      frame.blinking = seconds.truncatingRemainder(dividingBy: blinkInterval) >= blinkInterval - blinkDuration
    }
    if motions.contains(.yoyo) {
      let swing = 0.5 - 0.5 * cos(2 * .pi * seconds / yoyoPeriod)
      frame.yoyoDrop = yoyoDropRange.lowerBound + (yoyoDropRange.upperBound - yoyoDropRange.lowerBound) * swing
    }
    if motions.contains(.jump) {
      frame.jumpLift = jumpLift * max(0, sin(2 * .pi * seconds / jumpPeriod))
    }
    if motions.contains(.zzz) {
      frame.zzzPhase = seconds.truncatingRemainder(dividingBy: zzzPeriod) / zzzPeriod
    }
    return frame
  }
}

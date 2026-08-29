import Foundation

// MARK: - HeldProp

/// Something the tomato holds; it moves with the body.
enum HeldProp: Equatable {
  case drink
  case book
  case yoyo
  case cable
  case exclamation

  /// The book is held in front of the face with the hands over its covers; everything else sits in
  /// front of the hands.
  var drawnBehindHands: Bool {
    self == .book
  }
}

// MARK: - Furniture

/// Something the tomato sits at or on; drawn in canvas coordinates, unmoved by the body transform.
enum Furniture: Equatable {
  case laptop
  case sofa
}

// MARK: - Motion

enum Motion: Hashable {
  case blink
  case breathe
  case yoyo
  case jump
}

// MARK: - MascotPose

/// One pose of the mascot, as data. `rotation` is degrees about design point (50, 55); `scale` is
/// about the canvas origin; `offset` is design units applied after scaling.
struct MascotPose: Equatable {
  var eyes: Eyes
  var mouth: Mouth
  var leftArm: Arm
  var rightArm: Arm
  var held: HeldProp?
  var furniture: Furniture?
  var rotation: Double
  var scale: Double
  var offset: CGSize
  var motions: Set<Motion>

  /// The same pose frozen: eyes shut, nothing moving.
  func paused() -> MascotPose {
    var pose = self
    pose.eyes = .closed
    pose.motions = []
    return pose
  }
}

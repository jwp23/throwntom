import Foundation
import ThrowntomClient

extension MascotPose {
  /// Behind a laptop drawn side-on to its right, hands on the keyboard.
  static let work = MascotPose(
    eyes: .open,
    mouth: .smile,
    leftArm: Arm(22, 71, 25.5, 83.5, 32.1, 91.1, 47.2, 92.2),
    rightArm: Arm(78, 71, 77.2, 90.4, 76, 96.3, 70.7, 97.2),
    held: nil,
    furniture: .laptop,
    rotation: -12,
    scale: 1,
    offset: CGSize(width: -10, height: 0),
    motions: [.blink, .breathe],
  )

  /// Both hands on a cold drink, eyes closed.
  static let shortBreak = MascotPose(
    eyes: .closed,
    mouth: .smile,
    leftArm: Arm(22, 71, 16, 80, 22, 86, 35, 85),
    rightArm: Arm(78, 71, 88, 74, 84, 80, 71, 80),
    held: .drink,
    furniture: nil,
    rotation: -12,
    scale: 1,
    offset: .zero,
    motions: [.breathe],
  )

  /// Reading on the sofa; the tomato shrinks to 80% so the furniture fits the canvas.
  static let longBreak = MascotPose(
    eyes: .down,
    mouth: .smile,
    leftArm: Arm(22, 71, 16, 74, 22, 86, 34, 82),
    rightArm: Arm(78, 71, 84, 74, 78, 86, 66, 82),
    held: .book,
    furniture: .sofa,
    rotation: -10,
    scale: 0.8,
    offset: CGSize(width: 9.6, height: 8.4),
    motions: [.breathe],
  )

  /// Playing with a yo-yo, eyes on the disc.
  static let idle = MascotPose(
    eyes: .down,
    mouth: .smile,
    leftArm: Arm(22, 71, 10, 70, 11.8, 80.6, 24.6, 83.3),
    rightArm: Arm(78, 71, 82.1, 77.2, 84.3, 85.8, 77, 91.4),
    held: .yoyo,
    furniture: nil,
    rotation: -12,
    scale: 1,
    offset: CGSize(width: 0, height: -8),
    motions: [.breathe, .yoyo],
  )

  /// Arms up, eyes wide, mouth open; jumps until the user confirms.
  static let awaitingConfirm = MascotPose(
    eyes: .wide,
    mouth: .open,
    leftArm: Arm(22, 71, 10, 54, 10, 40, 20, 29),
    rightArm: Arm(78, 71, 90, 54, 90, 40, 80, 29),
    held: .exclamation,
    furniture: nil,
    rotation: -12,
    scale: 1,
    offset: .zero,
    motions: [.jump],
  )

  /// Holding a pulled-out cable, mouth flat.
  static let disconnected = MascotPose(
    eyes: .open,
    mouth: .flat,
    leftArm: Arm(22, 71, 16, 80, 22, 86, 35, 85),
    rightArm: Arm(78, 71, 84, 80, 78, 86, 65, 85),
    held: .cable,
    furniture: nil,
    rotation: -12,
    scale: 1,
    offset: .zero,
    motions: [.blink],
  )

  /// The pose for a daemon phase; `nil` is disconnected. Paused shows the pose of the phase that
  /// was paused, frozen.
  static func pose(for phase: DaemonState.Phase?, pausedFrom: DaemonState.Phase) -> MascotPose {
    switch phase {
    case .work: work
    case .shortBreak: shortBreak
    case .longBreak: longBreak
    case .idle: idle
    case .awaitingConfirm: awaitingConfirm
    case .paused: pose(for: pausedFrom == .paused ? .idle : pausedFrom, pausedFrom: .idle).paused()
    case nil: disconnected
    }
  }
}

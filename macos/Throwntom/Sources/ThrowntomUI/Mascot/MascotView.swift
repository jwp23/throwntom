import SwiftUI

// MARK: - CharacterLayer

/// One layer in the mascot character, in render order.
enum CharacterLayer: Hashable {
  case body
  case face
  case worn(WornProp)
  case arms
  case hands
  case held(HeldProp)
}

// MARK: - MascotCharacterView

/// The mascot at one instant: furniture, then the transformed character (body, face, arms, held
/// prop), with the motion frame applied on top of the pose.
struct MascotCharacterView: View {

  // MARK: Internal

  let pose: MascotPose
  let frame: MotionFrame
  let scheme: PhaseScheme
  let unit: CGFloat
  let animatesPoseChanges: Bool

  var body: some View {
    ZStack {
      if pose.furniture == .sofa {
        FurnitureView(furniture: .sofa, scheme: scheme, unit: unit)
      }
      character
      if pose.furniture == .laptop {
        FurnitureView(furniture: .laptop, scheme: scheme, unit: unit)
      }
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }

  /// A blink only shuts eyes that are open; wide, down and closed eyes stay as posed.
  static func eyes(for pose: MascotPose, frame: MotionFrame) -> Eyes {
    frame.blinking && pose.eyes == .open ? .closed : pose.eyes
  }

  /// Returns the ordered layers drawn for the given pose.
  static func layers(for pose: MascotPose) -> [CharacterLayer] {
    var result: [CharacterLayer] = [.body, .face]
    if let worn = pose.worn {
      result.append(.worn(worn))
    }
    result.append(.arms)
    if let held = pose.held, held.drawnBehindHands {
      result.append(.held(held))
    }
    result.append(.hands)
    if let held = pose.held, !held.drawnBehindHands {
      result.append(.held(held))
    }
    return result
  }

  // MARK: Private

  private var character: some View {
    ZStack {
      ForEach(Self.layers(for: pose), id: \.self) { layer in
        layerView(layer)
      }
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
    .rotationEffect(.degrees(pose.rotation + frame.bobDegrees), anchor: UnitPoint(x: 0.5, y: 0.55))
    .scaleEffect(pose.scale, anchor: .topLeading)
    .offset(x: pose.offset.width * unit, y: (pose.offset.height - frame.jumpLift) * unit)
    .animation(animatesPoseChanges ? MascotMotion.poseChange : nil, value: pose)
  }

  @ViewBuilder
  private func layerView(_ layer: CharacterLayer) -> some View {
    switch layer {
    case .body:
      TomatoBodyView(unit: unit)
    case .face:
      TomatoFaceView(eyes: Self.eyes(for: pose, frame: frame), mouth: pose.mouth, unit: unit)
    case .arms:
      ArmsView(left: pose.leftArm, right: pose.rightArm, unit: unit)
    case .hands:
      HandsView(left: pose.leftArm, right: pose.rightArm, unit: unit)
    case .held(let prop):
      HeldPropView(prop: prop, yoyoDrop: frame.yoyoDrop, unit: unit)
    case .worn(let prop):
      WornPropView(prop: prop, unit: unit)
    }
  }

}

// MARK: - MascotView

/// The mascot, sized by its container and animated by a clock that stops whenever the pose has
/// nothing to move or the user asked macOS for less motion.
struct MascotView: View {

  // MARK: Internal

  let pose: MascotPose
  let scheme: PhaseScheme

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation(paused: !animates)) { context in
        MascotCharacterView(
          pose: pose,
          frame: animates ? MascotMotion.frame(at: context.date.timeIntervalSince(start), motions: pose.motions) : .still,
          scheme: scheme,
          unit: geometry.size.width / Units.canvas,
          animatesPoseChanges: !reduceMotion,
        )
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }

  // MARK: Private

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date.now

  private var animates: Bool {
    !pose.motions.isEmpty && !reduceMotion
  }

}

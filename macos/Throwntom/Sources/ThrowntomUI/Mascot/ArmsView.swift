import SwiftUI

// MARK: - Arm

/// One arm: a cubic curve from the shoulder to the hand, in design units.
struct Arm: Equatable {
  init(_ sx: Double, _ sy: Double, _ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ hx: Double, _ hy: Double) {
    shoulder = CGPoint(sx, sy)
    control1 = CGPoint(c1x, c1y)
    control2 = CGPoint(c2x, c2y)
    hand = CGPoint(hx, hy)
  }

  init(shoulder: CGPoint, _ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ hx: Double, _ hy: Double) {
    self.shoulder = shoulder
    control1 = CGPoint(c1x, c1y)
    control2 = CGPoint(c2x, c2y)
    hand = CGPoint(hx, hy)
  }

  var shoulder: CGPoint
  var control1: CGPoint
  var control2: CGPoint
  var hand: CGPoint
}

// MARK: - ArmShape

/// The arm's stroke path. Every point is animatable, so a pose change bends the arm from one
/// curve into the next rather than cutting.
struct ArmShape: Shape {
  typealias ArmAnimatableData = AnimatablePair<
    AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
    AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
  >

  var arm: Arm

  var animatableData: ArmAnimatableData {
    get {
      AnimatablePair(
        AnimatablePair(arm.shoulder.animatableData, arm.control1.animatableData),
        AnimatablePair(arm.control2.animatableData, arm.hand.animatableData),
      )
    }
    set {
      arm.shoulder.animatableData = newValue.first.first
      arm.control1.animatableData = newValue.first.second
      arm.control2.animatableData = newValue.second.first
      arm.hand.animatableData = newValue.second.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let units = Units(rect: rect)
    var path = Path()
    path.move(to: units.point(arm.shoulder.x, arm.shoulder.y))
    path.addCurve(
      to: units.point(arm.hand.x, arm.hand.y),
      control1: units.point(arm.control1.x, arm.control1.y),
      control2: units.point(arm.control2.x, arm.control2.y),
    )
    return path
  }
}

// MARK: - HandShape

struct HandShape: Shape {
  static let radius: Double = 4

  var centre: CGPoint

  var animatableData: CGPoint.AnimatableData {
    get { centre.animatableData }
    set { centre.animatableData = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.circle(Units(rect: rect), centre.x, centre.y, Self.radius)
    return path
  }
}

// MARK: - ArmsView

/// Both arms as outline strokes.
struct ArmsView: View {
  let left: Arm
  let right: Arm
  let unit: CGFloat

  var body: some View {
    ZStack {
      ArmShape(arm: left).stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
      ArmShape(arm: right).stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }
}

// MARK: - HandsView

/// Both hand discs, filled with body colour and stroked.
struct HandsView: View {
  let left: Arm
  let right: Arm
  let unit: CGFloat

  var body: some View {
    ZStack {
      HandShape(centre: left.hand).fill(MascotPalette.body.color)
      HandShape(centre: left.hand).stroke(Palette.outline.color, lineWidth: 2 * unit)
      HandShape(centre: right.hand).fill(MascotPalette.body.color)
      HandShape(centre: right.hand).stroke(Palette.outline.color, lineWidth: 2 * unit)
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }
}

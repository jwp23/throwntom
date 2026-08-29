import SwiftUI

// MARK: - Units

/// The mascot is drawn on a 100×100 design canvas (`docs/designs/mascot-poses.html`); `Units` maps
/// those coordinates into whatever rect a Shape is given.
struct Units {
  static let canvas: CGFloat = 100

  let rect: CGRect

  var scale: CGFloat {
    rect.width / Self.canvas
  }

  func point(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: rect.minX + CGFloat(x) * scale, y: rect.minY + CGFloat(y) * scale)
  }

  func length(_ value: Double) -> CGFloat {
    CGFloat(value) * scale
  }
}

// MARK: - DesignShape

/// A Shape whose outline is written in design units.
struct DesignShape: Shape {
  let draw: @Sendable (inout Path, Units) -> Void

  func path(in rect: CGRect) -> Path {
    var path = Path()
    draw(&path, Units(rect: rect))
    return path
  }
}

extension CGPoint {
  /// A design-unit literal.
  init(_ x: Double, _ y: Double) {
    self.init(x: x, y: y)
  }
}

// MARK: - Path helpers

/// SVG-style path commands in design units, so the reference drawing transcribes line for line.
extension Path {
  mutating func move(_ units: Units, _ x: Double, _ y: Double) {
    move(to: units.point(x, y))
  }

  mutating func line(_ units: Units, _ x: Double, _ y: Double) {
    addLine(to: units.point(x, y))
  }

  mutating func curve(_ units: Units, _ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double, _ x: Double, _ y: Double) {
    addCurve(to: units.point(x, y), control1: units.point(c1x, c1y), control2: units.point(c2x, c2y))
  }

  mutating func quad(_ units: Units, _ cx: Double, _ cy: Double, _ x: Double, _ y: Double) {
    addQuadCurve(to: units.point(x, y), control: units.point(cx, cy))
  }

  mutating func circle(_ units: Units, _ cx: Double, _ cy: Double, _ r: Double) {
    let origin = units.point(cx - r, cy - r)
    addEllipse(in: CGRect(x: origin.x, y: origin.y, width: units.length(2 * r), height: units.length(2 * r)))
  }

  /// An ellipse centred at (cx, cy), rotated `rotation` degrees about its centre.
  mutating func ellipse(_ units: Units, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, rotation: Double = 0) {
    let centre = units.point(cx, cy)
    let transform = CGAffineTransform(translationX: centre.x, y: centre.y)
      .rotated(by: rotation * .pi / 180)
      .scaledBy(x: units.scale, y: units.scale)
    addPath(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry)).applying(transform))
  }

  mutating func polygon(_ units: Units, _ points: [(Double, Double)]) {
    guard let first = points.first else { return }
    move(units, first.0, first.1)
    for point in points.dropFirst() {
      line(units, point.0, point.1)
    }
    closeSubpath()
  }
}

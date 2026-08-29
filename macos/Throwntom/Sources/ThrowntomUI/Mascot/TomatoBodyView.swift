import SwiftUI

// MARK: - TomatoBody

/// The tomato's body, stem and leaves, drawn in design units.
enum TomatoBody {
  static let centre = CGPoint(50, 56)
  static let radius: Double = 34

  static let outline = DesignShape { path, units in
    path.circle(units, centre.x, centre.y, radius)
  }

  static let leaves = DesignShape { path, units in
    path.move(units, 50, 24)
    path.curve(units, 45, 12, 38, 8, 28, 11)
    path.curve(units, 34, 15, 40, 19, 43, 24)
    path.closeSubpath()
    path.move(units, 50, 24)
    path.curve(units, 55, 12, 62, 8, 72, 11)
    path.curve(units, 66, 15, 60, 19, 57, 24)
    path.closeSubpath()
  }

  static let stem = DesignShape { path, units in
    path.move(units, 50, 26)
    path.curve(units, 50, 20, 52, 14, 57, 9)
  }

  static let leafShading = LinearGradient(
    colors: [MascotPalette.leafLight.color, MascotPalette.leafDark.color],
    startPoint: UnitPoint(x: 0.28, y: 0.08),
    endPoint: UnitPoint(x: 0.72, y: 0.24),
  )

  /// Light falls from the upper left; the gradient is placed relative to the full canvas.
  static func shading(unit: CGFloat) -> RadialGradient {
    RadialGradient(
      colors: [MascotPalette.bodyLight.color, MascotPalette.body.color, MascotPalette.bodyDark.color],
      center: UnitPoint(x: 0.398, y: 0.424),
      startRadius: 0,
      endRadius: 54.4 * unit,
    )
  }
}

// MARK: - TomatoBodyView

/// Body, stem and leaves on a `100 * unit` square. The leaves are swept 8° to the right so the
/// crown follows the turned face.
struct TomatoBodyView: View {
  let unit: CGFloat

  var body: some View {
    ZStack {
      TomatoBody.outline.fill(TomatoBody.shading(unit: unit))
      TomatoBody.outline.stroke(Palette.outline.color, lineWidth: 2 * unit)
      ZStack {
        TomatoBody.leaves.fill(TomatoBody.leafShading)
        TomatoBody.leaves.stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
        TomatoBody.stem.stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round))
      }
      .rotationEffect(.degrees(8), anchor: UnitPoint(x: 0.5, y: 0.2))
      .offset(x: 4 * unit)
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }
}

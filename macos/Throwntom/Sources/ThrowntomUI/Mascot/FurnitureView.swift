import SwiftUI

// MARK: - FurnitureShapes

/// Things the tomato sits at or on, drawn in canvas units (unrotated).
enum FurnitureShapes {
  /// Laptop seen side-on at the tomato's right, screen hinged up and leaning toward it.
  static let laptopBase = DesignShape { path, units in
    path.polygon(units, [(60, 92), (96, 92), (96, 96), (60, 96)])
  }

  static let laptopScreen = DesignShape { path, units in
    path.polygon(units, [(94, 92), (84, 56), (88, 55), (98, 91)])
  }

  static let laptopGlow = DesignShape { path, units in
    path.move(units, 93, 90)
    path.line(units, 85, 60)
  }

  // Sofa: back, two arms, seat, legs.
  static let sofaBack = DesignShape { path, units in
    path.move(units, 12, 60)
    path.quad(units, 12, 54, 18, 54)
    path.line(units, 82, 54)
    path.quad(units, 88, 54, 88, 60)
    path.line(units, 88, 70)
    path.line(units, 12, 70)
    path.closeSubpath()
  }

  static let sofaBackSeam = DesignShape { path, units in
    path.move(units, 50, 54)
    path.line(units, 50, 70)
  }

  static let sofaArms = DesignShape { path, units in
    path.move(units, 6, 70)
    path.quad(units, 6, 64, 12, 64)
    path.line(units, 16, 64)
    path.line(units, 16, 90)
    path.line(units, 6, 90)
    path.closeSubpath()
    path.move(units, 94, 70)
    path.quad(units, 94, 64, 88, 64)
    path.line(units, 84, 64)
    path.line(units, 84, 90)
    path.line(units, 94, 90)
    path.closeSubpath()
  }

  static let sofaSeat = DesignShape { path, units in
    path.polygon(units, [(16, 72), (84, 72), (84, 90), (16, 90)])
  }

  static let sofaSeatSeam = DesignShape { path, units in
    path.move(units, 50, 72)
    path.line(units, 50, 90)
  }

  static let sofaLegs = DesignShape { path, units in
    path.move(units, 10, 90)
    path.line(units, 10, 96)
    path.move(units, 90, 90)
    path.line(units, 90, 96)
  }
}

// MARK: - FurnitureView

struct FurnitureView: View {

  // MARK: Internal

  let furniture: Furniture
  let scheme: PhaseScheme
  let unit: CGFloat

  var body: some View {
    ZStack {
      switch furniture {
      case .laptop: laptop
      case .sofa: sofa
      }
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }

  // MARK: Private

  private var outline: Color {
    Palette.outline.color
  }

  private var edge: StrokeStyle {
    StrokeStyle(lineWidth: 2 * unit, lineJoin: .round)
  }

  private var laptop: some View {
    ZStack {
      FurnitureShapes.laptopBase.fill(MascotPalette.propLight.color)
      FurnitureShapes.laptopBase.stroke(outline, style: edge)
      FurnitureShapes.laptopScreen.fill(MascotPalette.propDark.color)
      FurnitureShapes.laptopScreen.stroke(outline, style: edge)
      FurnitureShapes.laptopGlow.stroke(MascotPalette.sky.color, style: StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round))
    }
  }

  private var sofa: some View {
    ZStack {
      FurnitureShapes.sofaBack.fill(scheme.sofaBack.color)
      FurnitureShapes.sofaBack.stroke(outline, style: edge)
      FurnitureShapes.sofaBackSeam.stroke(outline.opacity(0.6), lineWidth: 1.5 * unit)
      FurnitureShapes.sofaArms.fill(scheme.sofaArm.color)
      FurnitureShapes.sofaArms.stroke(outline, style: edge)
      FurnitureShapes.sofaSeat.fill(scheme.sofaSeat.color)
      FurnitureShapes.sofaSeat.stroke(outline, style: edge)
      FurnitureShapes.sofaSeatSeam.stroke(outline.opacity(0.6), lineWidth: 1.5 * unit)
      FurnitureShapes.sofaLegs.stroke(outline, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
    }
  }

}

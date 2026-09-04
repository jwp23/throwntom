import SwiftUI

// MARK: - WornProps

/// Props the tomato wears, in body-local design units. The body circle is centred (50, 56) with
/// radius 34 and the eyes sit at y 54-55, so "ear height" is the rim either side of y 51.
enum WornProps {
  /// The band, arcing over the crown from cup to cup. It peaks below the leaves (which start at
  /// y 24) so the crown still reads as a tomato rather than a head in a hat.
  static let headsetBand = DesignShape { path, units in
    path.move(units, 19, 45)
    path.curve(units, 22, 26, 78, 24, 81, 43)
  }

  /// The far cup, on the side the three-quarter face is turned away from, so it is the smaller one.
  static let headsetFarCup = DesignShape { path, units in
    path.ellipse(units, 19, 52, 5, 7)
  }

  static let headsetNearCup = DesignShape { path, units in
    path.ellipse(units, 81, 50, 6.5, 8.5)
  }

  /// The plate on the near cup: the one light note in an otherwise dark accessory, so the cup does
  /// not read as a hole in the silhouette.
  static let headsetNearCupPlate = DesignShape { path, units in
    path.ellipse(units, 81, 50, 3, 4.5)
  }

  /// The boom, leaving the near cup and curving forward to the near corner of the mouth.
  static let headsetBoom = DesignShape { path, units in
    path.move(units, 80, 57)
    path.curve(units, 79, 64, 75, 68, 69, 69)
  }

  static let headsetMic = DesignShape { path, units in
    path.circle(units, 69, 69, 2.6)
  }
}

// MARK: - WornPropView

/// Something the tomato wears. Drawn inside the character transform, unlike `Furniture`, so it
/// turns and breathes with the body it is worn on.
struct WornPropView: View {

  // MARK: Internal

  let prop: WornProp
  let unit: CGFloat

  var body: some View {
    ZStack {
      switch prop {
      case .headset: headset
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

  /// The band and boom are stroked twice, the wider outline pass first, because a stroke cannot be
  /// outlined the way a filled shape can.
  private var headset: some View {
    ZStack {
      WornProps.headsetBand.stroke(outline, style: StrokeStyle(lineWidth: 5.5 * unit, lineCap: .round))
      WornProps.headsetBand.stroke(MascotPalette.propDark.color, style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round))
      WornProps.headsetBoom.stroke(outline, style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round))
      WornProps.headsetBoom.stroke(MascotPalette.propDark.color, style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round))
      WornProps.headsetMic.fill(MascotPalette.propDark.color)
      WornProps.headsetMic.stroke(outline, lineWidth: 1.5 * unit)
      WornProps.headsetFarCup.fill(MascotPalette.propDark.color)
      WornProps.headsetFarCup.stroke(outline, style: edge)
      WornProps.headsetNearCup.fill(MascotPalette.propDark.color)
      WornProps.headsetNearCup.stroke(outline, style: edge)
      WornProps.headsetNearCupPlate.fill(MascotPalette.propLight.color)
    }
  }

}

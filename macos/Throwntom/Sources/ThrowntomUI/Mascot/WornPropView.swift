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

  /// The pads, one per cup, each half its own cup across. A pair of ears is a pair: two cups
  /// painted differently read as a mistake rather than as perspective, so both carry the same
  /// mark and only the size differs, which is what the three-quarter turn actually changes.
  static let headsetFarCupPad = DesignShape { path, units in
    path.ellipse(units, 19, 52, 2.5, 3.5)
  }

  static let headsetNearCupPad = DesignShape { path, units in
    path.ellipse(units, 81, 50, 3.25, 4.25)
  }

  /// The boom, leaving the near cup and curving down the jaw to the open cheek. It stops short of
  /// the mouth, which a capsule held against the smile merges with, and short of the body rim,
  /// where one disappears into the outline it is sitting on.
  static let headsetBoom = DesignShape { path, units in
    path.move(units, 80, 58)
    path.curve(units, 80.5, 64, 78, 69, 74, 71.5)
  }

  /// How far the capsule is tilted off horizontal, in degrees. Named because it is the angle of
  /// the boom's descent, and a test measures the bar's own proportions by undoing it.
  static let headsetMicTilt = -30.0

  /// The capsule: a bar rather than a dot, tilted along the boom's descent so it points at the
  /// mouth. A circle here read as a spot that happened to be on the cheek.
  static let headsetMic = DesignShape { path, units in
    path.roundedRect(units, 74, 71.8, 3.1, 1.8, radius: 1.8, rotation: headsetMicTilt)
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
      // Drawn as heavily as the band it comes off: a hairline boom left the capsule looking
      // unattached, and the line from ear to mouth is what says the capsule is a microphone.
      WornProps.headsetBoom.stroke(outline, style: StrokeStyle(lineWidth: 5 * unit, lineCap: .round))
      WornProps.headsetBoom.stroke(MascotPalette.propDark.color, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
      // The capsule wears the cups' shell rather than the band's dark: a dark blob this close to
      // the body outline reads as part of the outline, which is what stopped it saying microphone.
      WornProps.headsetMic.fill(MascotPalette.propLight.color)
      WornProps.headsetMic.stroke(outline, lineWidth: 1.5 * unit)
      // The cups are the laptop's pairing the same way round — the light shell carries the dark
      // pad — so the headset belongs to the same set of hardware the tomato already owns, and
      // reads against the red body rather than sinking into its own outline.
      WornProps.headsetFarCup.fill(MascotPalette.propLight.color)
      WornProps.headsetFarCup.stroke(outline, style: edge)
      WornProps.headsetFarCupPad.fill(MascotPalette.propDark.color)
      WornProps.headsetNearCup.fill(MascotPalette.propLight.color)
      WornProps.headsetNearCup.stroke(outline, style: edge)
      WornProps.headsetNearCupPad.fill(MascotPalette.propDark.color)
    }
  }

}

import SwiftUI

// MARK: - Eyes

enum Eyes: Equatable {
  case open
  case closed
  case down
  case wide
}

// MARK: - Mouth

enum Mouth: Equatable {
  case smile
  case open
  case flat
  case grin
}

// MARK: - TomatoFace

/// The three-quarter face: features shifted to the right (near) side, far eye smaller, so the
/// tomato reads as turned slightly away.
enum TomatoFace {
  static let glint = DesignShape { path, units in
    path.ellipse(units, 30, 35, 5, 2.5, rotation: -40)
  }

  static let farCheek = DesignShape { path, units in
    path.ellipse(units, 34, 64, 6, 3.5)
  }

  static let nearCheek = DesignShape { path, units in
    path.ellipse(units, 74, 63, 6, 3.5)
  }

  static let catchlights = DesignShape { path, units in
    path.circle(units, 48, 54, 1)
    path.circle(units, 67, 53, 1.2)
  }

  static let widePupils = DesignShape { path, units in
    path.circle(units, 48, 55, 2.5)
    path.circle(units, 67, 54, 2.8)
  }

  /// The outline of both eyes: filled discs when open, a stroked lid when closed or looking down.
  static func eyeOutline(_ eyes: Eyes) -> DesignShape {
    switch eyes {
    case .open:
      DesignShape { path, units in
        path.circle(units, 47, 55, 3.5)
        path.circle(units, 66, 54, 4)
      }

    case .closed:
      DesignShape { path, units in
        path.move(units, 43, 55)
        path.quad(units, 47, 58, 51, 55)
        path.move(units, 62, 54)
        path.quad(units, 66, 57, 70, 54)
      }

    case .down:
      DesignShape { path, units in
        path.move(units, 43, 57)
        path.quad(units, 47, 54, 51, 57)
        path.move(units, 62, 56)
        path.quad(units, 66, 53, 70, 56)
      }

    case .wide:
      DesignShape { path, units in
        path.circle(units, 47, 55, 5)
        path.circle(units, 66, 54, 5.5)
      }
    }
  }

  static func mouthShape(_ mouth: Mouth) -> DesignShape {
    switch mouth {
    case .smile:
      DesignShape { path, units in
        path.move(units, 50, 66)
        path.quad(units, 58, 73, 66, 65)
      }

    case .open:
      DesignShape { path, units in path.ellipse(units, 58, 69, 4, 5) }

    case .flat:
      DesignShape { path, units in
        path.move(units, 52, 68)
        path.line(units, 64, 67)
      }

    case .grin:
      DesignShape { path, units in
        path.move(units, 48, 65)
        path.quad(units, 58, 78, 68, 64)
        path.closeSubpath()
      }
    }
  }
}

// MARK: - TomatoFaceView

struct TomatoFaceView: View {

  // MARK: Internal

  let eyes: Eyes
  let mouth: Mouth
  let unit: CGFloat

  var body: some View {
    ZStack {
      TomatoFace.glint.fill(Palette.cream.color.opacity(0.5))
      TomatoFace.farCheek.fill(MascotPalette.blush.color.opacity(0.7))
      TomatoFace.nearCheek.fill(MascotPalette.blush.color.opacity(0.8))
      eyesView
      mouthView
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }

  // MARK: Private

  @ViewBuilder
  private var eyesView: some View {
    switch eyes {
    case .open:
      TomatoFace.eyeOutline(.open).fill(Palette.outline.color)
      TomatoFace.catchlights.fill(Palette.white.color)

    case .closed,
         .down:
      TomatoFace.eyeOutline(eyes).stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round))

    case .wide:
      TomatoFace.eyeOutline(.wide).fill(Palette.white.color)
      TomatoFace.eyeOutline(.wide).stroke(Palette.outline.color, lineWidth: 1.5 * unit)
      TomatoFace.widePupils.fill(Palette.outline.color)
    }
  }

  @ViewBuilder
  private var mouthView: some View {
    switch mouth {
    case .smile,
         .flat:
      TomatoFace.mouthShape(mouth).stroke(Palette.outline.color, style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
    case .open,
         .grin:
      TomatoFace.mouthShape(mouth).fill(Palette.outline.color)
    }
  }

}

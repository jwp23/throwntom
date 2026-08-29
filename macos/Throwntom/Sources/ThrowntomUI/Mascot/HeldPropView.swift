import SwiftUI

// MARK: - HeldProps

/// Props the tomato holds, in body-local design units, transcribed from `docs/designs/mascot-poses.html`.
enum HeldProps {
  /// Cold drink, right hand.
  static let drinkCup = DesignShape { path, units in
    path.polygon(units, [(64, 70), (78, 70), (76, 92), (66, 92)])
  }

  static let drinkLiquid = DesignShape { path, units in
    path.move(units, 66, 78)
    path.line(units, 77, 78)
  }

  static let drinkStraw = DesignShape { path, units in
    path.move(units, 72, 70)
    path.line(units, 75, 60)
  }

  static let drinkLime = DesignShape { path, units in
    path.polygon(units, [(78, 66), (70, 70), (72, 62)])
  }

  /// Book seen from behind: spine nearest, covers receding, page edges along the top.
  static let bookPages = DesignShape { path, units in
    path.polygon(units, [(31, 70), (50, 76), (69, 70), (69, 66), (50, 72), (31, 66)])
  }

  static let bookLeftCover = DesignShape { path, units in
    path.polygon(units, [(50, 104), (50, 76), (31, 70), (31, 94)])
  }

  static let bookRightCover = DesignShape { path, units in
    path.polygon(units, [(50, 104), (50, 76), (69, 70), (69, 94)])
  }

  static let bookSpine = DesignShape { path, units in
    path.move(units, 50, 76)
    path.line(units, 50, 104)
  }

  // Yo-yo from the right hand. The string hangs along the canvas vertical, which in body-local
  // units (the body is rotated -12°) is this direction.
  static let yoyoHand = CGPoint(77, 91.4)
  static let yoyoDirection = CGPoint(-0.208, 0.978)
  static let yoyoAcross = CGPoint(0.978, 0.208)
  static let yoyoDiscRadius = 5.5

  /// A yanked cable, one end in each hand.
  static let cableLeft = DesignShape { path, units in
    path.move(units, 35, 85)
    path.curve(units, 40, 95, 48, 95, 50, 90)
  }

  static let cablePlug = DesignShape { path, units in
    path.polygon(units, [(50, 87), (56, 87), (56, 93), (50, 93)])
  }

  static let cableProngs = DesignShape { path, units in
    path.move(units, 56, 88.5)
    path.line(units, 60, 88.5)
    path.move(units, 56, 91.5)
    path.line(units, 60, 91.5)
  }

  static let cableRight = DesignShape { path, units in
    path.move(units, 65, 85)
    path.curve(units, 72, 88, 80, 92, 88, 88)
  }

  static let cableSocket = DesignShape { path, units in
    path.polygon(units, [(88, 84.5), (96, 84.5), (96, 91.5), (88, 91.5)])
  }

  static let cableSocketHoles = DesignShape { path, units in
    path.circle(units, 91, 88, 0.9)
    path.circle(units, 93.5, 88, 0.9)
  }

  /// The "!" beside a raised hand.
  static let exclamation = DesignShape { path, units in
    path.move(units, 88, 6)
    path.line(units, 88, 16)
    path.move(units, 88, 20)
    path.line(units, 88, 22)
  }

  static func yoyoEnd(drop: Double) -> CGPoint {
    CGPoint(yoyoHand.x + yoyoDirection.x * drop, yoyoHand.y + yoyoDirection.y * drop)
  }

  static func yoyoString(drop: Double) -> DesignShape {
    DesignShape { path, units in
      path.move(units, yoyoHand.x, yoyoHand.y)
      let end = yoyoEnd(drop: drop)
      path.line(units, end.x, end.y)
    }
  }

  static func yoyoDisc(drop: Double) -> DesignShape {
    DesignShape { path, units in
      let end = yoyoEnd(drop: drop + yoyoDiscRadius)
      path.circle(units, end.x, end.y, yoyoDiscRadius)
    }
  }

  static func yoyoAxle(drop: Double) -> DesignShape {
    DesignShape { path, units in
      let end = yoyoEnd(drop: drop + yoyoDiscRadius)
      path.circle(units, end.x, end.y, 1.5)
    }
  }

  static func yoyoGroove(drop: Double) -> DesignShape {
    DesignShape { path, units in
      let centre = yoyoEnd(drop: drop + yoyoDiscRadius)
      let across = CGPoint(yoyoAcross.x * yoyoDiscRadius, yoyoAcross.y * yoyoDiscRadius)
      path.move(units, centre.x - across.x, centre.y - across.y)
      path.line(units, centre.x + across.x, centre.y + across.y)
    }
  }
}

// MARK: - HeldPropView

struct HeldPropView: View {

  // MARK: Internal

  let prop: HeldProp
  /// How far the yo-yo hangs below the hand, in design units; ignored by every other prop.
  let yoyoDrop: Double
  let unit: CGFloat

  var body: some View {
    ZStack {
      switch prop {
      case .drink: drink
      case .book: book
      case .yoyo: yoyo
      case .cable: cable
      case .exclamation:
        HeldProps.exclamation.stroke(Palette.cream.color, style: StrokeStyle(lineWidth: 4 * unit, lineCap: .round))
      }
    }
    .frame(width: Units.canvas * unit, height: Units.canvas * unit)
  }

  // MARK: Private

  private var outline: Color {
    Palette.outline.color
  }

  private var drink: some View {
    ZStack {
      HeldProps.drinkCup.fill(Palette.cream.color)
      HeldProps.drinkCup.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.drinkLiquid.stroke(MascotPalette.sky.color, lineWidth: 5 * unit)
      HeldProps.drinkStraw.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round))
      HeldProps.drinkLime.fill(MascotPalette.leafLight.color)
      HeldProps.drinkLime.stroke(outline, lineWidth: 1.5 * unit)
    }
  }

  private var book: some View {
    ZStack {
      HeldProps.bookPages.fill(Palette.cream.color)
      HeldProps.bookPages.stroke(outline, style: StrokeStyle(lineWidth: 1.5 * unit, lineJoin: .round))
      HeldProps.bookLeftCover.fill(MascotPalette.wood.color)
      HeldProps.bookRightCover.fill(MascotPalette.wood.darkened(by: 0.1).color)
      HeldProps.bookLeftCover.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.bookRightCover.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.bookSpine.stroke(outline, style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round))
    }
  }

  private var yoyo: some View {
    ZStack {
      HeldProps.yoyoString(drop: yoyoDrop).stroke(outline, lineWidth: 1.5 * unit)
      HeldProps.yoyoDisc(drop: yoyoDrop).fill(MascotPalette.sky.color)
      HeldProps.yoyoDisc(drop: yoyoDrop).stroke(outline, lineWidth: 2 * unit)
      HeldProps.yoyoGroove(drop: yoyoDrop).stroke(outline, lineWidth: 1.5 * unit)
      HeldProps.yoyoAxle(drop: yoyoDrop).fill(outline)
    }
  }

  private var cable: some View {
    ZStack {
      HeldProps.cableLeft.stroke(
        Palette.cream.color,
        style: StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round, lineJoin: .round),
      )
      HeldProps.cableRight.stroke(
        Palette.cream.color,
        style: StrokeStyle(lineWidth: 2.5 * unit, lineCap: .round, lineJoin: .round),
      )
      HeldProps.cablePlug.fill(Palette.cream.color)
      HeldProps.cablePlug.stroke(outline, lineWidth: 1.5 * unit)
      HeldProps.cableProngs.stroke(outline, style: StrokeStyle(lineWidth: 1.5 * unit, lineCap: .round))
      HeldProps.cableSocket.fill(Palette.cream.color)
      HeldProps.cableSocket.stroke(outline, lineWidth: 1.5 * unit)
      HeldProps.cableSocketHoles.fill(outline)
    }
  }

}

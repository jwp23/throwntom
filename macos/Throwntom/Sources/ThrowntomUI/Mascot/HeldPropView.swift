import SwiftUI

// MARK: - HeldProps

/// Props the tomato holds, in body-local design units.
enum HeldProps {

  // MARK: Internal

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

  /// A cheeseburger held between both hands. A domed bun over a flat base is a silhouette
  /// nothing else in the set has, which is what a stack of bread slices lacked: at mascot size
  /// the outline is all that survives, and a sandwich's outline is a rectangle.
  static let burgerTopBun = DesignShape { path, units in
    path.move(units, 44, 85)
    path.curve(units, 44, 71, 69, 71, 69, 85)
    path.line(units, 44, 85)
  }

  static let burgerSeeds = DesignShape { path, units in
    path.circle(units, 51, 77.5, 1.1)
    path.circle(units, 57, 75.5, 1.1)
    path.circle(units, 63, 78, 1.1)
  }

  /// Cheese, with the corners drooping past the patty so the edge is ragged, not straight.
  static let burgerCheese = DesignShape { path, units in
    path.polygon(units, [
      (43.5, 85),
      (69.5, 85),
      (69.5, 88),
      (66, 91.5),
      (63, 88),
      (57, 88),
      (54, 91.5),
      (51, 88),
      (47, 88),
      (43.5, 88),
    ])
  }

  static let burgerPatty = DesignShape { path, units in
    path.polygon(units, [(44.5, 88), (68.5, 88), (68.5, 92), (44.5, 92)])
  }

  static let burgerBottomBun = DesignShape { path, units in
    path.polygon(units, [(45.5, 92), (67.5, 92), (67.5, 97), (45.5, 97)])
  }

  /// The "!" beside a raised hand.
  static let exclamation = DesignShape { path, units in
    path.move(units, 88, 6)
    path.line(units, 88, 16)
    path.move(units, 88, 20)
    path.line(units, 88, 22)
  }

  /// The nightcap: a cone pulled down where the crown was, its brim riding the top of the head and
  /// its point flopped to the near side. Past the crest at (38, 2) the top edge is a straight
  /// taper — the sharp angle there is what keeps it a cap and not a pillow. It replaces the crown
  /// outright: the asleep pose is not `crowned`, because the crown is drawn swept far enough right
  /// (`TomatoBodyView`) that no cap this thin could cover its tip.
  static let nightcapCone = DesignShape { path, units in
    path.move(units, 18, 33)
    path.curve(units, 16, 26, 17, 16, 25, 8)
    path.curve(units, 26, 5, 34, 4, 38, 2)
    path.line(units, 74, 8)
    path.curve(units, 73, 12.5, 70, 17, 66, 22)
    path.curve(units, 52, 21, 32, 25, 18, 33)
    path.closeSubpath()
  }

  /// The brim, along the bottom edge of the cone and stroked over it, so the band reads as turned
  /// up rather than as a line ruled across the cap.
  static let nightcapBrim = DesignShape { path, units in
    path.move(units, 18, 33)
    path.curve(units, 32, 25, 52, 21, 66, 22)
  }

  static let nightcapBobble = DesignShape { path, units in
    path.circle(units, 77, 9, 4.8)
  }

  /// How many Z's drift off the cap at once.
  static let zedCount = 3

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

  /// Where one of the `zedCount` Z's is in its own run, 0 to 1. They share a cycle staggered by
  /// even fractions of it, so at any instant — a still frame included — one is setting off, one is
  /// halfway and one is leaving.
  static func zedProgress(_ index: Int, phase: Double) -> Double {
    (phase + Double(index) / Double(zedCount)).truncatingRemainder(dividingBy: 1)
  }

  /// A Z at `progress` through its run: rising away from the cap and growing as it goes, which is
  /// what reads as drifting off rather than sliding across.
  static func zed(progress: Double) -> DesignShape {
    let half = zedHalfSizeRange.lowerBound
      + (zedHalfSizeRange.upperBound - zedHalfSizeRange.lowerBound) * progress
    let x = zedStart.x + zedDrift.width * progress
    let y = zedStart.y + zedDrift.height * progress
    return DesignShape { path, units in
      path.move(units, x - half, y - half)
      path.line(units, x + half, y - half)
      path.line(units, x - half, y + half)
      path.line(units, x + half, y + half)
    }
  }

  /// A Z dissolves over the last of its run instead of blinking off at the top of it. It is fully
  /// painted everywhere else, so a still frame keeps all three.
  static func zedOpacity(progress: Double) -> Double {
    min(1, (1 - progress) / zedFadeOut)
  }

  // MARK: Private

  /// Where a Z sets off — beside the cheek, under the cap's flopped point — and how far it travels
  /// over its run: up and away from the face, into the corner the "!" used to shout from. The climb
  /// is long enough that Z's a third of a cycle apart never touch, so they read as three.
  private static let zedStart = CGPoint(79, 38)
  private static let zedDrift = CGSize(width: 16, height: -31)
  private static let zedHalfSizeRange: ClosedRange<Double> = 2 ... 4.5
  /// The last fraction of a run, over which the Z fades out.
  private static let zedFadeOut = 0.25

}

// MARK: - HeldPropView

struct HeldPropView: View {

  // MARK: Internal

  let prop: HeldProp
  /// How far the yo-yo hangs below the hand, in design units; ignored by every other prop.
  let yoyoDrop: Double
  /// Where the nightcap's Z's are in their cycle, 0 to 1; ignored by every other prop.
  let zzzPhase: Double
  let unit: CGFloat

  var body: some View {
    ZStack {
      switch prop {
      case .drink: drink
      case .book: book
      case .yoyo: yoyo
      case .cable: cable
      case .burger: burger
      case .nightcap: nightcap
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

  private var burger: some View {
    ZStack {
      HeldProps.burgerBottomBun.fill(MascotPalette.wood.color)
      HeldProps.burgerBottomBun.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.burgerPatty.fill(MascotPalette.wood.darkened(by: 0.15).color)
      HeldProps.burgerPatty.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.burgerCheese.fill(MascotPalette.cheese.color)
      HeldProps.burgerCheese.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.burgerTopBun.fill(MascotPalette.wood.color)
      HeldProps.burgerTopBun.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.burgerSeeds.fill(Palette.cream.color)
    }
  }

  /// Cream cap, sky brim, cream Z's: the cap borrows the drink's and the yo-yo's own blue rather
  /// than introducing a colour, and the Z's are the cream the "!" they replace was drawn in.
  private var nightcap: some View {
    ZStack {
      HeldProps.nightcapCone.fill(Palette.cream.color)
      HeldProps.nightcapCone.stroke(outline, style: StrokeStyle(lineWidth: 2 * unit, lineJoin: .round))
      HeldProps.nightcapBrim.stroke(outline, style: StrokeStyle(lineWidth: 6.5 * unit, lineCap: .round))
      HeldProps.nightcapBrim.stroke(MascotPalette.sky.color, style: StrokeStyle(lineWidth: 4.5 * unit, lineCap: .round))
      HeldProps.nightcapBobble.fill(Palette.cream.color)
      HeldProps.nightcapBobble.stroke(outline, lineWidth: 2 * unit)
      zeds
    }
  }

  private var zeds: some View {
    ForEach(0 ..< HeldProps.zedCount, id: \.self) { index in
      let progress = HeldProps.zedProgress(index, phase: zzzPhase)
      HeldProps.zed(progress: progress)
        .stroke(Palette.cream.color, style: StrokeStyle(lineWidth: 1.6 * unit, lineCap: .round, lineJoin: .round))
        .opacity(HeldProps.zedOpacity(progress: progress))
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

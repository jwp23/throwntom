import SwiftUI
import XCTest
@testable import ThrowntomUI

/// The dim itself: that it is drawn, and that what it is drawn at is still readable.
@MainActor
final class ShortcutRowTests: XCTestCase {

  // MARK: Internal

  /// The row is *drawn* at the opacity its own constant names — not merely that the constant holds
  /// it. Two rows differing in nothing but `isEnabled` are rendered and their ink compared; the
  /// ratio is the opacity the body applied, so a body that stops applying it, or applies some other
  /// value, fails here. The expectation is read from the constant, so changing the constant moves
  /// the expectation with it.
  func testAnUnavailableRowIsDrawnAtTheOpacityItsConstantNames() throws {
    let available = try ink(of: row(isEnabled: true))
    let unavailable = try ink(of: row(isEnabled: false))

    XCTAssertGreaterThan(available, 0, "nothing was drawn, so there is nothing to compare")
    XCTAssertEqual(
      unavailable / available,
      ShortcutRow.unavailableOpacity,
      accuracy: 0.01,
      "the row is not drawn at the opacity `unavailableOpacity` names",
    )
  }

  /// The dim is the row's whole answer to "can I press this now", and it is drawn — a reader who
  /// cannot see it is told nothing at all. `DESIGN.md` does not let a meaning rest on how something
  /// is painted, so the row says it in the title cell, the way a task row says "focused" aloud.
  func testAnUnavailableRowSaysSoAloud() {
    XCTAssertEqual(ShortcutRow(entry: Self.entry(isEnabled: true)).spokenTitle, "Pause")
    XCTAssertEqual(ShortcutRow(entry: Self.entry(isEnabled: false)).spokenTitle, "Pause, unavailable")
  }

  /// Why the constant is 0.55 and not lower. `DESIGN.md` bans dimming a shortcut because a dimmed
  /// hint stops clearing 4.5:1, and the exception it records for this sheet is only defensible
  /// while the dimmed row still clears it. Both surfaces the sheet is drawn on are checked: a light
  /// window, where the label is black on white, and a dark one, where it is white on macOS's
  /// near-black window background.
  func testADimmedRowStillClearsTheContrastFloor() {
    for (name, label, ground) in Self.surfaces {
      let dimmed = Self.composite(label, over: ground, opacity: ShortcutRow.unavailableOpacity)

      XCTAssertGreaterThanOrEqual(Contrast.ratio(dimmed, ground), 4.5, "a dimmed row on a \(name) sheet")
    }
  }

  // MARK: Private

  /// The two window backgrounds the sheet is drawn on, with the label colour macOS puts on each.
  private static let surfaces: [(name: String, label: HexColor, ground: HexColor)] = [
    ("light", HexColor("#000000"), HexColor("#FFFFFF")),
    ("dark", HexColor("#FFFFFF"), HexColor("#1E1E1E")),
  ]

  /// `colour` painted over `ground` at `opacity`, which is what `.opacity` leaves on screen.
  private static func composite(_ colour: HexColor, over ground: HexColor, opacity: Double) -> HexColor {
    let bytes = (0 ..< 3).map { channel in
      Int(((colour.channel(channel) * opacity + ground.channel(channel) * (1 - opacity)) * 255).rounded())
    }
    return HexColor(String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
  }

  /// The same row either way round, so nothing but `isEnabled` can differ between two of them.
  private static func entry(isEnabled: Bool) -> ShortcutList.Entry {
    ShortcutList.Entry(
      title: "Pause",
      hint: "⌘⇧P",
      condition: "while a phase is running or paused",
      isEnabled: isEnabled,
    )
  }

  /// One row, in a `Grid` because that is what a `GridRow` lays itself out in.
  private func row(isEnabled: Bool) -> some View {
    Grid { ShortcutRow(entry: Self.entry(isEnabled: isEnabled)) }.frame(width: 400)
  }

  /// How much the drawing paints, summed over every pixel's alpha. Drawing the same words at half
  /// the opacity leaves half the ink.
  private func ink(of view: some View) throws -> Double {
    let rep = try AppearanceRender.bitmap(view, appearance: .aqua, scheme: .light)
    var total = 0.0
    for y in 0 ..< rep.pixelsHigh {
      for x in 0 ..< rep.pixelsWide {
        total += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
      }
    }
    return total
  }

}

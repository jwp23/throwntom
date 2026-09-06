import SwiftUI
import XCTest
@testable import ThrowntomUI

/// The dim itself: that it is drawn, and that what it is drawn at is still readable.
@MainActor
final class ShortcutRowTests: XCTestCase {

  // MARK: Internal

  /// The title and hint cells are *drawn* at the opacity the constant names — not merely that the
  /// constant holds it. Two rows differing in nothing but `isEnabled` are rendered and their ink
  /// compared; the condition column is left out of the fixture (empty string, no ink of its own) so
  /// the ratio measures only the two cells the row's own state actually dims, not the condition,
  /// which is dimmed independent of it (see `testTheConditionColumnIsAlwaysDimmedTheSameAmount`).
  func testAnUnavailableRowIsDrawnAtTheOpacityItsConstantNames() throws {
    let available = try ink(of: row(isEnabled: true, condition: ""))
    let unavailable = try ink(of: row(isEnabled: false, condition: ""))

    XCTAssertGreaterThan(available, 0, "nothing was drawn, so there is nothing to compare")
    XCTAssertEqual(
      unavailable / available,
      ShortcutRow.unavailableOpacity,
      accuracy: 0.01,
      "the title and hint are not drawn at the opacity `unavailableOpacity` names",
    )
  }

  /// The condition column reads as a footnote to the title in every row, not only a dimmed one —
  /// compounding `unavailableOpacity` on top of an already-dimmed row is what fails the contrast
  /// floor below, so the column carries that opacity once, on its own, whatever `isEnabled` is.
  /// Two rows differing only in `isEnabled` still paint the same ink for the same condition text.
  func testTheConditionColumnIsAlwaysDimmedTheSameAmount() throws {
    let condition = "while a phase is running or paused"

    let enabled = try ink(of: row(isEnabled: true, condition: condition))
      - ink(of: row(isEnabled: true, condition: ""))
    let disabled = try ink(of: row(isEnabled: false, condition: condition))
      - ink(of: row(isEnabled: false, condition: ""))

    XCTAssertGreaterThan(enabled, 0, "nothing was drawn, so there is nothing to compare")
    XCTAssertEqual(enabled, disabled, accuracy: 0.5, "the condition column dims with the row's own state")
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
  ///
  /// The condition column is held to the same floor at the same opacity — `unavailableOpacity`
  /// applied once, never stacked with anything else. `.foregroundStyle(.secondary)` was tried first
  /// and failed this: `NSColor.secondaryLabelColor` resolves to the same label colour as `.primary`
  /// at roughly half opacity (measured: 0.498 on aqua, 0.549 on darkAqua), and composited with
  /// `unavailableOpacity` on top — the way an already-dimmed row would have drawn it — that lands at
  /// 1.96:1 on the light appearance, nowhere near 4.5:1. Both compositions are asserted below so a
  /// change that stacks the two dims again fails here before it fails a reader's eyes.
  func testADimmedRowStillClearsTheContrastFloor() {
    for (name, label, secondaryAlpha, ground) in Self.surfaces {
      let title = Self.composite(label, over: ground, opacity: ShortcutRow.unavailableOpacity)
      let condition = Self.composite(label, over: ground, opacity: ShortcutRow.unavailableOpacity)
      let secondaryStackedWithTheRowsOwnDim = Self.composite(
        label,
        over: ground,
        opacity: secondaryAlpha * ShortcutRow.unavailableOpacity,
      )

      XCTAssertGreaterThanOrEqual(Contrast.ratio(title, ground), 4.5, "a dimmed title on a \(name) sheet")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(condition, ground), 4.5, "the condition column on a \(name) sheet")
      XCTAssertLessThan(
        Contrast.ratio(secondaryStackedWithTheRowsOwnDim, ground),
        4.5,
        "the rejected `.secondary` design should still fail on a \(name) sheet",
      )
    }
  }

  // MARK: Private

  /// The two window backgrounds the sheet is drawn on, with the label colour macOS puts on each and
  /// the alpha `.secondary` resolves to there (`NSColor.secondaryLabelColor`, measured as above) —
  /// kept only to document why that design was rejected.
  private static let surfaces: [(name: String, label: HexColor, secondaryAlpha: Double, ground: HexColor)] = [
    ("light", HexColor("#000000"), 0.498, HexColor("#FFFFFF")),
    ("dark", HexColor("#FFFFFF"), 0.549, HexColor("#1E1E1E")),
  ]

  /// `colour` painted over `ground` at `opacity`, which is what `.opacity` leaves on screen.
  private static func composite(_ colour: HexColor, over ground: HexColor, opacity: Double) -> HexColor {
    let bytes = (0 ..< 3).map { channel in
      Int(((colour.channel(channel) * opacity + ground.channel(channel) * (1 - opacity)) * 255).rounded())
    }
    return HexColor(String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
  }

  /// The same row either way round, so nothing but `isEnabled` can differ between two of them.
  private static func entry(isEnabled: Bool, condition: String = "while a phase is running or paused") -> ShortcutList.Entry {
    ShortcutList.Entry(
      title: "Pause",
      hint: "⌘⇧P",
      condition: condition,
      isEnabled: isEnabled,
    )
  }

  /// One row, in a `Grid` because that is what a `GridRow` lays itself out in.
  private func row(isEnabled: Bool, condition: String = "while a phase is running or paused") -> some View {
    Grid { ShortcutRow(entry: Self.entry(isEnabled: isEnabled, condition: condition)) }.frame(width: 400)
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

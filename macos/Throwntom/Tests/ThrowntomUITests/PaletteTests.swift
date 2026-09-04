import ThrowntomClient
import XCTest
@testable import ThrowntomUI

final class PaletteTests: XCTestCase {
  func testEveryPhaseHasAScheme() {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused] {
      XCTAssertNotEqual(Palette.scheme(for: phase), Palette.scheme(for: nil), "\(phase) must not fall back to disconnected")
    }
  }

  func testTextOnGroundMeetsAA() {
    for (name, s) in Palette.schemes {
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.text, s.ground), 4.5, "\(name) text on ground")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.primaryChipText, s.primaryChip), 4.5, "\(name) primary chip text")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.secondaryChipText, s.secondaryChip), 4.5, "\(name) secondary chip text")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.panelText, s.panel), 4.5, "\(name) panel text")
    }
  }

  func testChipsAreDistinguishableFromGround() {
    for (name, s) in Palette.schemes {
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.primaryChip, s.ground), 3, "\(name) primary chip on ground")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.secondaryChip, s.ground), 3, "\(name) secondary chip on ground")
      // Panel vs ground only needs a visible step, not a text-contrast ratio: disconnected is
      // 1.18, the six phases are ≈1.74.
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.panel, s.ground), 1.15, "\(name) panel on ground")
    }
  }

  /// The star marking a focused task is the one mark on the ground that used to carry a colour of
  /// its own — `Color.yellow` — instead of the surface's. It reads as text, so it clears the text
  /// bar (throwntom-bxd.15).
  func testTheFocusStarClearsEverySurfaceItSitsOn() {
    for (name, s) in Palette.schemes {
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.taskMark, s.ground), 4.5, "\(name) task mark on ground")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(s.panelTaskMark, s.panel), 4.5, "\(name) task mark on panel")
    }
  }

  /// Why the star gave up its tint: system yellow never went through the gate above, and the idle
  /// ground is where it lands worst. Pinned as a number so the sentence in DESIGN.md has something
  /// behind it, and so a future tint has to be measured rather than eyeballed.
  func testSystemYellowWouldNotClearTheIdleGround() {
    XCTAssertLessThan(Contrast.ratio(HexColor("#FFCC00"), Palette.scheme(for: .idle).ground), 2)
  }

  func testContrastRatioMatchesWCAGReference() {
    XCTAssertEqual(Contrast.ratio(HexColor("#FFFFFF"), HexColor("#000000")), 21, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(HexColor("#F68C31"), HexColor("#000000")), 8.71, accuracy: 0.05)
  }

  func testHexColorRoundTripsToSRGB() throws {
    let c = try XCTUnwrap(NSColor(HexColor("#1F130C").color).usingColorSpace(.sRGB))
    XCTAssertEqual(Int((c.redComponent * 255).rounded()), 0x1F)
    XCTAssertEqual(Int((c.greenComponent * 255).rounded()), 0x13)
    XCTAssertEqual(Int((c.blueComponent * 255).rounded()), 0x0C)
  }

  func testDarkenedScalesEveryChannel() {
    XCTAssertEqual(HexColor("#FFFFFF").darkened(by: 0.5).hex, "#808080")
    XCTAssertEqual(HexColor("#5A8CE0").darkened(by: 0).hex, "#5A8CE0")
    XCTAssertEqual(HexColor("#5A8CE0").darkened(by: 1).hex, "#000000")
  }

  func testSofaTonesDarkenTheGround() {
    let scheme = Palette.scheme(for: .longBreak)
    XCTAssertEqual(scheme.sofaBack, scheme.panel)
    XCTAssertEqual(scheme.sofaArm.hex, "#4971B5")
    XCTAssertEqual(scheme.sofaSeat.hex, "#517ECA")
    XCTAssertGreaterThan(Contrast.ratio(scheme.sofaArm, scheme.ground), 1.1)
  }
}

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
}

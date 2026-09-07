import ThrowntomClient
import XCTest
@testable import ThrowntomUI

final class PaletteTests: XCTestCase {
  func testEveryPhaseHasAScheme() {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .lunch, .awaitingConfirm, .paused] {
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
  ///
  /// This is an alias-integrity check, not independent contrast coverage: `taskMark` and
  /// `panelTaskMark` are defined as `text` and `panelText` (see `PhaseScheme.taskMark`), so the
  /// contrast ratios themselves are already proven by `testTextOnGroundMeetsAA`. What this test
  /// guards is that the alias holds — that nobody gives the mark a colour of its own again
  /// without updating this assertion.
  func testTheFocusStarClearsEverySurfaceItSitsOn() {
    for (name, s) in Palette.schemes {
      XCTAssertEqual(s.taskMark, s.text, "\(name) task mark should alias text")
      XCTAssertEqual(s.panelTaskMark, s.panelText, "\(name) panel task mark should alias panel text")
    }
  }

  /// Historical documentation, not a regression guard: the star no longer carries `Color.yellow`
  /// at all, so this exercises no shipped code path. It pins the 1.8:1 number that DESIGN.md's
  /// prose cites as the reason the star dropped its own tint, so that sentence stays backed by a
  /// measured value instead of a claim nothing checks.
  func testSystemYellowWouldNotClearTheIdleGround() {
    XCTAssertEqual(Contrast.ratio(HexColor("#FFCC00"), Palette.scheme(for: .idle).ground), 1.8, accuracy: 0.1)
  }

  /// A snooze is not a phase — the daemon reports it beside the state — so its ground is a scheme
  /// of its own rather than an eighth case of `scheme(for:)`. What matters is that it is nobody
  /// else's ground: while snoozed the window used to wear the alarm red it had just been asked to
  /// quiet, and any ground it shares with a phase puts it back in that position.
  func testTheSnoozedGroundBelongsToNoPhase() {
    for (name, scheme) in Palette.schemes where scheme != Palette.snoozed {
      XCTAssertNotEqual(scheme.ground, Palette.snoozed.ground, name)
    }
    XCTAssertNotEqual(Palette.snoozed, Palette.scheme(for: .awaitingConfirm), "the evening snooze")
    XCTAssertNotEqual(Palette.snoozed, Palette.scheme(for: .idle), "the morning one")
  }

  /// The chip and panel are the ground under the same black every phase scheme uses, so the three
  /// tokens are one colour seen three ways rather than three colours that happen to sit together.
  func testTheSnoozedChipAndPanelAreItsOwnGroundDarkened() {
    XCTAssertEqual(Palette.snoozed.secondaryChip.hex, Palette.snoozed.ground.darkened(by: 0.55).hex)
    XCTAssertEqual(Palette.snoozed.panel.hex, Palette.snoozed.ground.darkened(by: 0.28).hex)
  }

  /// The measurements the ground was chosen on, pinned as numbers. The gates above sweep every
  /// scheme and would pass a ground that had drifted to the edge of them; these say where this one
  /// actually sits, so a nudge to the hue has to be re-measured rather than eyeballed.
  func testTheSnoozedSchemeSitsWhereItWasMeasured() {
    let s = Palette.snoozed
    XCTAssertEqual(Contrast.ratio(s.text, s.ground), 5.57, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(s.primaryChipText, s.primaryChip), 15.60, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(s.secondaryChipText, s.secondaryChip), 10.37, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(s.panelText, s.panel), 5.31, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(s.secondaryChip, s.ground), 3.18, accuracy: 0.01)
    XCTAssertEqual(Contrast.ratio(s.panel, s.ground), 1.74, accuracy: 0.01)
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

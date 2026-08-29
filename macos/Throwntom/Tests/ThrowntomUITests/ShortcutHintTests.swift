import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutHintTests: XCTestCase {
  func testHintsAreBodySizedMonospacedAndNotLightweight() {
    XCTAssertEqual(ShortcutHint.font, Font.body.monospaced().weight(.medium))
  }

  func testHintsCarryTheFullTextColourOfTheirPanel() {
    // The hint inherits the panel's text colour rather than dimming it, so the ratio
    // PaletteTests already guarantees for panel text is the ratio the hint reads at.
    for (name, scheme) in Palette.schemes {
      XCTAssertEqual(ShortcutHint.color(on: scheme), scheme.panelText, "\(name)")
      XCTAssertGreaterThanOrEqual(Contrast.ratio(ShortcutHint.color(on: scheme), scheme.panel), 4.5, "\(name) hint")
    }
  }

  func testHintBodyBuilds() {
    _ = ShortcutHint(TaskHints.line).body
  }
}

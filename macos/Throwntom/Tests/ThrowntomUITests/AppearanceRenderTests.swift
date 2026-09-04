import AppKit
import SwiftUI
import XCTest
@testable import ThrowntomUI

/// The harness's own negative control.
///
/// Every appearance assertion on the snooze surfaces is of the form "this looks the same under
/// both". That shape passes just as happily if the sweep never happened: a harness that rendered
/// one appearance twice would take every one of those tests green while proving nothing — and the
/// bug they exist to catch is a field that goes black on black in Dark Mode (throwntom-bxd.3).
///
/// So something has to come out of the renderer *differently* under the two. A system colour does,
/// because it is defined by the appearance rather than by the palette — which is exactly why the
/// window paints itself from `Palette` and not from one of these.
///
/// It is `colorScheme` that this pins, deliberately: that is the knob `ImageRenderer` reads. See
/// `AppearanceRender`'s own note on why the `NSAppearance` half currently measures nothing.
@MainActor
final class AppearanceRenderTests: XCTestCase {
  func testTheAppearanceSweepReallyDrawsDifferently() throws {
    let systemInk = Rectangle().fill(Color(nsColor: .textColor)).frame(width: 8, height: 8)

    let light = try AppearanceRender.bitmap(systemInk, appearance: .aqua, scheme: .light)
    let dark = try AppearanceRender.bitmap(systemInk, appearance: .darkAqua, scheme: .dark)

    XCTAssertNotEqual(
      try AppearanceRender.png(light),
      try AppearanceRender.png(dark),
      "the appearance sweep is inert, so every same-under-both assertion on it is vacuous",
    )
  }
}

import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutHintTests: XCTestCase {

  // MARK: Internal

  func testHintsAreBodySizedMonospacedAndNotLightweight() {
    XCTAssertEqual(ShortcutHint.font, Font.body.monospaced().weight(.medium))
  }

  func testHintBodyBuilds() {
    _ = ShortcutHint(TaskHints.line(focused: false)).body
  }

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed. A
  /// statement that stops being built changes this string. ShortcutHint.swift:25:5.
  func testBodyIsTheTextFontedAndFixedSize() {
    XCTAssertEqual(shape(of: ShortcutHint("⌘⇧P").body), "ModifiedContent<Text, _FixedSizeLayout>")
  }

  /// `.fixedSize(horizontal: false, vertical: true)`: compressible in width, so a long hint wraps
  /// at whatever width the row gives it instead of demanding its own single-line width, but not
  /// in height, so a squeezed row still draws the whole wrapped hint rather than a fragment
  /// clipped to fit. One render, squeezed in both dimensions at once, kills both booleans: a
  /// `horizontal: true` mutant refuses to wrap, so it stays on one line and never reaches past the
  /// squeezed height; a `vertical: false` mutant wraps but is then clipped to the squeezed height.
  /// Only the unmutated pairing does both — wraps into several lines and draws all of them.
  /// Technique from `WindowNotesWrappingTests.assertWrapsRatherThanClipping`, which the doc
  /// comment on `ShortcutHint` already draws the parallel to. ShortcutHint.swift:27:30/27:47.
  func testTheHintWrapsRatherThanBeingClippedWhenSqueezed() throws {
    let ink = try inkHeight(
      of: ShortcutHint(Self.longHint).frame(width: Self.squeezeWidth, height: Self.squeezeHeight, alignment: .top),
      width: Self.squeezeWidth,
      canvasHeight: 300,
    )

    XCTAssertGreaterThan(
      ink,
      Self.squeezeHeight * 2,
      "the hint was clipped to its squeezed height instead of wrapping past it",
    )
  }

  // MARK: Private

  /// Long enough that at `squeezeWidth` it needs several lines, so a container squeezing its
  /// height to about one line's worth would clip it if the hint were compressible there.
  private static let longHint = "one two three four five six seven eight nine ten eleven twelve"

  private static let squeezeWidth: CGFloat = 120
  private static let squeezeHeight: CGFloat = 24

}

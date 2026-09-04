import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozedLineTests: XCTestCase {

  // MARK: Internal

  func testTheLineBuildsCountingAndStill() {
    _ = SnoozedLine(note: Self.note, remaining: "09:12").body
    _ = SnoozedLine(note: Self.note, remaining: nil).body
  }

  /// A deferred reminder has nothing else on screen to show for it, and this line is what the user
  /// looks at to find out when it comes back. A caption made it the smallest thing in the window
  /// (throwntom-bxd.4); it reads at the size of the window's other status text, in the ground's own
  /// ink, in both system appearances.
  func testTheLineReadsAsTheWindowsOtherStatusTextDoes() throws {
    let line = SnoozedLine(note: Self.note, remaining: "09:12")
    for appearance in AppearanceRender.appearances {
      let drawn = try bitmap(line.body, appearance: appearance)
      let reference = try bitmap(Text(Self.note).font(.body), appearance: appearance)
      // Two blank pictures are also identical, so the reference has to be shown to have ink on it.
      let ink = try AppearanceRender.swatch(
        Self.scheme.text,
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      XCTAssertGreaterThan(AppearanceRender.pixels(of: ink, in: reference), 20, appearance.name)
      XCTAssertEqual(
        try AppearanceRender.png(drawn),
        try AppearanceRender.png(reference),
        appearance.name,
      )
    }
  }

  /// The comparison above is only worth anything if it can tell one text style from another, which
  /// is the whole thing the line got wrong.
  func testACaptionDrawsASmallerLineThanTheStatusTextItIsMeasuredAgainst() throws {
    let caption = try AppearanceRender.size(Text(Self.note).font(.caption))
    let body = try AppearanceRender.size(Text(Self.note).font(.body))
    XCTAssertLessThan(caption.height, body.height)
    XCTAssertLessThan(caption.width, body.width)
  }

  // MARK: Private

  private static let note = "Snoozed · 09:12 left"

  /// The line only ever shows over a phase ground: a snooze is something a running daemon is doing.
  private static let scheme = Palette.scheme(for: .awaitingConfirm)

  private func bitmap(
    _ view: some View,
    appearance: (name: String, appearance: NSAppearance.Name, scheme: ColorScheme),
  ) throws -> NSBitmapImageRep {
    try AppearanceRender.bitmap(
      AppearanceRender.onGround(view, scheme: Self.scheme, width: 200, height: 24),
      appearance: appearance.appearance,
      scheme: appearance.scheme,
    )
  }

}

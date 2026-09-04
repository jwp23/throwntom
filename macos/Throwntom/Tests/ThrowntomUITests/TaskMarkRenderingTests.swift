import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - TaskMarkRenderingTests

/// That the focus mark is *drawn* in the surface's own colour, not merely that a property says so.
///
/// `PaletteTests` holds `taskMark` to 4.5:1 and `WindowSectionBodyTests` checks the property the
/// body reads, but neither runs the body: with both of them green a view can still draw the star
/// in `Color.yellow`, which is the thing throwntom-bxd.15 was filed about. Rendering the same
/// view under two schemes whose marks differ is what closes that: a body that ignores the colour
/// it is handed produces the same image twice.
@MainActor
final class TaskMarkRenderingTests: XCTestCase {

  // MARK: Internal

  /// `macos-work` marks in ink, `macos-disconnected` in cream — the widest pair in the palette.
  func testTheFocusSectionDrawsTheStarInTheSchemesOwnColour() throws {
    let ink = try render(FocusSection(tasks: [makeTask(id: 1, description: "write")], scheme: .work))
    let cream = try render(FocusSection(tasks: [makeTask(id: 1, description: "write")], scheme: .disconnected))

    XCTAssertNotEqual(ink, cream, "the focus star is drawn in a fixed colour, not the scheme's")
  }

  func testATaskRowDrawsItsMarkInTheColourItIsHanded() throws {
    let ink = try render(row(markColor: PhaseScheme.work.taskMark))
    let cream = try render(row(markColor: PhaseScheme.disconnected.taskMark))

    XCTAssertNotEqual(ink, cream, "the row's mark is drawn in a fixed colour, not the one passed in")
  }

  // MARK: Private

  private func row(markColor: HexColor) -> TaskRow {
    TaskRow(task: makeTask(id: 1, description: "write"), focused: true, markColor: markColor)
  }

  /// PNG bytes of the view drawn on a fixed neutral ground, so the only thing that can differ
  /// between two renders is what the view itself draws.
  private func render(_ view: some View) throws -> Data {
    let renderer = ImageRenderer(
      content: view
        .frame(width: 200, alignment: .leading)
        .padding(8)
        .background(Color.gray)
    )
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.nsImage, "the view did not render")
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    return try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
  }

}

extension PhaseScheme {
  fileprivate static let work = Palette.scheme(for: .work)
  fileprivate static let disconnected = Palette.scheme(for: nil)
}

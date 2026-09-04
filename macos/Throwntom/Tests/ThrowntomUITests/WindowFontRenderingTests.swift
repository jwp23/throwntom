import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// That a note and a focus row are *drawn* at the size their constant names, not merely that the
/// constant holds it.
///
/// `WindowSectionBodyTests` compares `WindowNotes.font` and `FocusSection.font` against the values
/// they should hold, but nothing there runs the body: with it green a body can still say
/// `.font(.caption)` and ship the smallest type in the window for the one account of a refusal —
/// which is what throwntom-bxd.14 and .15 were filed about. This is the font counterpart of
/// `TaskMarkRenderingTests`, and it closes the same gap the same way, by rendering.
///
/// Rendering a font has no second input the way a mark has two schemes, so the measurement is a
/// difference rather than a comparison against a reference view. One hard line break is added to
/// the text and the view is rendered twice; the growth is the line height of whatever font the
/// body actually applied. Everything else the view draws — padding, spacing, a section label, the
/// star, a button — is identical in both renders and cancels, so this survives layout edits that a
/// hand-built `.caption` twin of the view would break on. The size it is held to is read from the
/// constant, so a constant that changes moves the expectation with it: what fails is a body that
/// stops following it.
@MainActor
final class WindowFontRenderingTests: XCTestCase {

  // MARK: Internal

  func testANoteIsDrawnAtTheSizeItsConstantNames() throws {
    let responder = AppEnvironment(transport: try StubTransport(states: [])).responder

    try assertDrawnAtItsOwnSize(named: WindowNotes.font, "the note") {
      WindowNotes(error: nil, notice: $0, responder: responder)
    }
  }

  func testAFocusRowIsDrawnAtTheSizeItsConstantNames() throws {
    let scheme = Palette.scheme(for: .work)

    try assertDrawnAtItsOwnSize(named: FocusSection.font, "the focus row") {
      FocusSection(tasks: [makeTask(id: 1, description: $0)], scheme: scheme)
    }
  }

  // MARK: Private

  /// The text style a note or a focus row must not quietly fall back to: the smallest in the
  /// window, and the whole point of the two beads above.
  private static let tooSmall = Font.caption

  /// Renders `make(text)` with and without one extra line and holds the growth to the line height
  /// `named` draws at. `tooSmall` is measured too and asserted different, because a difference the
  /// probe cannot see would make the comparison below pass for the wrong reason.
  private func assertDrawnAtItsOwnSize(
    named font: Font,
    _ subject: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ make: (String) -> some View,
  ) throws {
    let drawn = try lineHeight(make)
    let named = try lineHeight { Text($0).font(font) }
    let smaller = try lineHeight { Text($0).font(Self.tooSmall) }

    XCTAssertNotEqual(
      named,
      smaller,
      "the two sizes render alike here, so this test could not tell them apart",
      file: file,
      line: line,
    )
    XCTAssertEqual(
      drawn,
      named,
      "\(subject) is not drawn at the size its own constant names",
      file: file,
      line: line,
    )
  }

  /// What one more line of text adds to the view's height — the line height of the font the body
  /// applied to it. `Text` breaks on the newline, so this is one extra line at any font size,
  /// with no dependence on where the string would have wrapped.
  private func lineHeight(_ make: (String) -> some View) throws -> CGFloat {
    try renderedHeight(make("A\nB")) - renderedHeight(make("A"))
  }

  /// The view's drawn height at a fixed width. Only the width is constrained: the height is what
  /// is being measured.
  private func renderedHeight(_ view: some View) throws -> CGFloat {
    let renderer = ImageRenderer(content: view.frame(width: 200, alignment: .leading))
    renderer.scale = 2
    return try XCTUnwrap(renderer.nsImage, "the view did not render").size.height
  }

}

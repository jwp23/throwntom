import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// Each sentence in `WindowNotes` carries `.fixedSize(horizontal: false, vertical: true)`:
/// compressible in width, so it wraps at whatever width the window gives it, but not in height,
/// so a container short on room gets the whole sentence rather than a fragment clipped to fit.
///
/// `WindowFontRenderingTests` measures a font by the height one more line adds, with no height
/// constraint on the container — under that rig `vertical: true` and `vertical: false` render
/// identically, because nothing is squeezing the view in the first place. What tells them apart
/// is a container that actually proposes too little height, which is what `assertWrapsRatherThanClipping`
/// sets up below.
@MainActor
final class WindowNotesWrappingTests: XCTestCase {

  // MARK: Internal

  func testTheNoticeWrapsRatherThanBeingClippedWhenSqueezed() throws {
    let responder = AppEnvironment(transport: try StubTransport(states: [])).responder

    try assertWrapsRatherThanClipping(
      WindowNotes(error: nil, notice: Self.longSentence, responder: responder)
    )
  }

  func testTheErrorWrapsRatherThanBeingClippedWhenSqueezed() throws {
    let responder = AppEnvironment(transport: try StubTransport(states: [])).responder

    try assertWrapsRatherThanClipping(
      WindowNotes(error: Self.longSentence, notice: nil, responder: responder)
    )
  }

  func testTheAuthorizationProblemWrapsRatherThanBeingClippedWhenSqueezed() async throws {
    let responder = try await makeResponderWithAProblem()

    try assertWrapsRatherThanClipping(
      WindowNotes(error: nil, notice: nil, responder: responder)
    )
  }

  /// The button is drawn under the sentence, not merely present somewhere in the body: this
  /// fails whether the button is dropped whole or just left inert, since either way nothing new
  /// is drawn below the sentence.
  func testOpenNotificationSettingsButtonIsDrawnBelowTheProblem() async throws {
    let responder = try await makeResponderWithAProblem()
    let problem = try XCTUnwrap(responder.authorization.problem)

    let withButton = try Self.renderedHeight(
      WindowNotes(error: nil, notice: nil, responder: responder),
      width: Self.wideWidth,
    )
    let sentenceAlone = try Self.renderedHeight(
      Text(problem).font(WindowNotes.font),
      width: Self.wideWidth,
    )

    XCTAssertGreaterThan(
      withButton,
      sentenceAlone + Self.buttonMargin,
      "no room below the sentence for the Open Notification Settings… button",
    )
  }

  // MARK: Private

  /// Long enough that at `squeezeWidth` it needs several lines, so a container squeezing its
  /// height to about one line's worth would clip it if the sentence were compressible there.
  private static let longSentence =
    "one two three four five six seven eight nine ten eleven twelve thirteen fourteen"

  private static let wideWidth: CGFloat = 300
  private static let squeezeWidth: CGFloat = 120
  private static let squeezeHeight: CGFloat = 24
  /// Comfortably less than a button's own height, so a real button reliably clears it.
  private static let buttonMargin: CGFloat = 12

  private static func renderedHeight(_ view: some View, width: CGFloat) throws -> CGFloat {
    let renderer = ImageRenderer(content: view.frame(width: width, alignment: .leading))
    renderer.scale = 1
    return try XCTUnwrap(renderer.nsImage, "the view did not render").size.height
  }

  /// The height of the lowest non-white pixel row: how far the view actually drew, regardless of
  /// what size its enclosing frame reports upward. A `.frame(width:height:)` always reports its
  /// own fixed size to its parent no matter what its child does, so measuring that reported size
  /// cannot tell a wrapped sentence from a clipped one - only the pixels can.
  private static func inkHeight(of view: some View, width: CGFloat, canvasHeight: CGFloat) throws -> CGFloat {
    let renderer = ImageRenderer(
      content: view.frame(width: width, height: canvasHeight, alignment: .top).background(Color.white)
    )
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.nsImage, "the view did not render")
    let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let data = try XCTUnwrap(cgImage.dataProvider?.data)
    let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
    let bytesPerRow = cgImage.bytesPerRow

    var lastInkedRow = 0
    for y in 0..<cgImage.height {
      for x in 0..<cgImage.width {
        let offset = y * bytesPerRow + x * 4
        if pixels[offset] < 250 || pixels[offset + 1] < 250 || pixels[offset + 2] < 250 {
          lastInkedRow = y
          break
        }
      }
    }
    return CGFloat(lastInkedRow + 1)
  }

  private func makeResponderWithAProblem() async throws -> ReminderResponder {
    let responder = AppEnvironment(
      transport: try StubTransport(states: []),
      authorizer: StubAuthorizer(refusal: notificationsNotAllowed),
    ).responder
    await responder.requestAuthorization()
    return responder
  }

  /// Proposes `view` only `squeezeHeight` of height - about one line - inside a much taller
  /// canvas, then measures how far down the render actually drew. A sentence that refuses
  /// vertical compression draws its full wrapped height past that boundary; one that accepts
  /// compression, or is missing outright, does not.
  private func assertWrapsRatherThanClipping(
    _ view: some View,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let squeezed = VStack(alignment: .leading, spacing: 0) {
      view.frame(width: Self.squeezeWidth, height: Self.squeezeHeight, alignment: .top)
    }
    let ink = try Self.inkHeight(of: squeezed, width: Self.squeezeWidth, canvasHeight: 300)

    XCTAssertGreaterThan(
      ink,
      Self.squeezeHeight * 2,
      "the sentence was clipped to its squeezed height instead of wrapping past it",
      file: file,
      line: line,
    )
  }

}

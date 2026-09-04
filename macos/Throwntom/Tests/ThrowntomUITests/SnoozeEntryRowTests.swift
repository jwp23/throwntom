import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozeEntryRowTests: XCTestCase {

  // MARK: Internal

  func testAWholeNumberOfMinutesIsSnoozedAndClosesTheField() throws {
    let (row, transport, model, refusals) = try makeRow()
    row.submit("45")

    XCTAssertEqual(refusals.count, 0, "a valid duration must not beep")
    XCTAssertFalse(model.isEnteringSnooze, "the field closes once it is answered")
    try waitForRequest(transport)
    XCTAssertEqual(
      transport.requests,
      [StubTransport.Request(method: "POST", path: "/v1/timer/snooze", body: #"{"minutes":45}"#)],
    )
  }

  /// A refusal keeps the field open with the text intact: the user mistyped, and retyping from
  /// scratch is a worse answer than correcting.
  func testARefusedDurationBeepsAndLeavesTheFieldOpen() throws {
    for entry in ["", "  ", "0", "-1", "abc", "1.5", "90m", "99999"] {
      let (row, transport, model, refusals) = try makeRow()
      row.submit(entry)
      XCTAssertEqual(refusals.count, 1, entry)
      XCTAssertTrue(model.isEnteringSnooze, entry)
      XCTAssertEqual(transport.requests.count, 0, entry)
    }
  }

  func testTheRowBuilds() throws {
    let (row, _, _, _) = try makeRow()
    _ = row.body
  }

  /// The default `alert` is the real beep, not a stub — worth building at least once so the
  /// default value itself is exercised rather than only the overridden one every other test uses.
  func testTheRowBuildsWithItsDefaultAlert() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    _ = SnoozeEntryRow(client: environment.client, model: environment.windowModel).body
  }

  /// A field the system draws takes the *system appearance's* background while the text on it stays
  /// this window's ink — black on black in Dark Mode (throwntom-bxd.3). The field has to be painted
  /// in the app's own paper instead, which is a thing that can be looked for in the pixels: a
  /// system-drawn control comes back from the renderer as a placeholder, never as this colour.
  func testTheFieldIsPaintedInTheAppsOwnPaper() throws {
    let (row, _, _, _) = try makeRow()
    for appearance in AppearanceRender.appearances {
      let drawn = try AppearanceRender.bitmap(
        AppearanceRender.onGround(row.field, scheme: scheme, width: 120, height: 40),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let paper = try AppearanceRender.swatch(
        Palette.cream,
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      XCTAssertGreaterThan(AppearanceRender.pixels(of: paper, in: drawn), 200, appearance.name)
    }
  }

  /// The rule is a caption, not a dimmed one. `.secondary` drops it well under the 4.5:1 every
  /// other line on these grounds clears (`PaletteTests`, and the same call `WindowNotes` makes for
  /// the sentences under the chips), and it is the line a user reads *because* they got the
  /// duration wrong. Drawn against plain caption text, it has to be the same picture.
  func testTheRuleIsCaptionTextInTheWindowsOwnColourRatherThanDimmed() throws {
    let (row, _, _, _) = try makeRow()
    let plain = Text("1 to \(SnoozeDraft.maximumMinutes) minutes").font(.caption)
    for appearance in AppearanceRender.appearances {
      let drawn = try AppearanceRender.bitmap(
        AppearanceRender.onGround(row.rule, scheme: scheme, width: 140, height: 20),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let reference = try AppearanceRender.bitmap(
        AppearanceRender.onGround(plain, scheme: scheme, width: 140, height: 20),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      // Two blank pictures are also identical, so the reference has to be shown to be a line of
      // text. Counted against an empty box rather than by ink pixels: caption glyphs are thin
      // enough that antialiasing leaves only a handful at the full colour.
      let blank = try AppearanceRender.bitmap(
        AppearanceRender.onGround(Color.clear, scheme: scheme, width: 140, height: 20),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      XCTAssertNotEqual(
        try AppearanceRender.png(reference),
        try AppearanceRender.png(blank),
        appearance.name,
      )
      XCTAssertEqual(
        try AppearanceRender.png(drawn),
        try AppearanceRender.png(reference),
        appearance.name,
      )
    }
  }

  /// What the user types is content, not a footnote about it: the row reads at the window's body
  /// size, and only the rule under it is a caption. Measured by forcing the whole row to caption —
  /// a row that was already one would not get any smaller, and `rule` sets its own font either way.
  func testTheRowItselfIsBodyTextAndOnlyTheRuleIsACaption() throws {
    let (row, _, _, _) = try makeRow()

    XCTAssertGreaterThan(
      try AppearanceRender.size(row.body).height,
      try AppearanceRender.size(row.body.font(.caption)).height,
    )
  }

  // MARK: Private

  /// A counter the row can report a refusal into, so the beep is observable.
  private final class RefusalLog {
    var count = 0
  }

  /// The row only ever opens over a phase ground, since the snooze chip that opens it is only
  /// offered for a state that can snooze.
  private let scheme = Palette.scheme(for: .awaitingConfirm)

  private func makeRow() throws -> (SnoozeEntryRow, StubTransport, WindowModel, RefusalLog) {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    let model = environment.windowModel
    model.isEnteringSnooze = true
    let refusals = RefusalLog()
    let row = SnoozeEntryRow(client: environment.client, model: model) { refusals.count += 1 }
    return (row, transport, model, refusals)
  }

  private func waitForRequest(_ transport: StubTransport) throws {
    let deadline = Date().addingTimeInterval(2)
    while transport.requests.isEmpty, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

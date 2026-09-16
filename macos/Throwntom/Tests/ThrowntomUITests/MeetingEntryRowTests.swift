import AppKit
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class MeetingEntryRowTests: XCTestCase {

  // MARK: Internal

  func testAWholeNumberOfMinutesStartsAMeetingAndClosesTheField() throws {
    let (row, transport, model, refusals) = try makeRow()
    row.submit("45")

    XCTAssertEqual(refusals.count, 0, "a valid length must not beep")
    XCTAssertFalse(model.isEnteringMeeting, "the field closes once it is answered")
    try waitForRequest(transport)
    XCTAssertEqual(
      transport.requests,
      [StubTransport.Request(method: "POST", path: "/v1/timer/meeting", body: #"{"minutes":45}"#)],
    )
  }

  /// A refusal keeps the field open with the text intact: the user mistyped, and retyping from
  /// scratch is a worse answer than correcting.
  func testARefusedLengthBeepsAndLeavesTheFieldOpen() throws {
    for entry in ["", "  ", "0", "-1", "abc", "1.5", "90m", "99999"] {
      let (row, transport, model, refusals) = try makeRow()
      row.submit(entry)
      XCTAssertEqual(refusals.count, 1, entry)
      XCTAssertTrue(model.isEnteringMeeting, entry)
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
    _ = MeetingEntryRow(client: environment.client, model: environment.windowModel).body
  }

  /// The same call the snooze field makes, for the same reason: a system-drawn field takes the
  /// system appearance's background while the text on it stays this window's ink, which is black
  /// on black in Dark Mode. Painted in the app's own paper, the colour is there in the pixels.
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

  /// The rule is a caption in the ground's full text colour rather than a dimmed one: it is the
  /// line a user reads *because* the length they typed was refused. Drawn against plain caption
  /// text, it has to be the same picture.
  func testTheRuleIsCaptionTextInTheWindowsOwnColourRatherThanDimmed() throws {
    let (row, _, _, _) = try makeRow()
    let plain = Text("1 to \(Minutes.maximum) minutes").font(.caption)
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
      // text before matching against it means anything.
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
  /// size, and only the rule under it is a caption.
  func testTheRowItselfIsBodyTextAndOnlyTheRuleIsACaption() throws {
    let (row, _, _, _) = try makeRow()

    XCTAssertGreaterThan(
      try AppearanceRender.size(row.body).height,
      try AppearanceRender.size(row.body.font(.caption)).height,
    )
  }

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed. Either unit
  /// label ceasing to be built changes this string. MeetingEntryRow.swift:21:9, :23:9.
  func testBodyIsTheRuleUnderALabeledFieldFlankedByItsUnitLabels() throws {
    let (row, _, _, _) = try makeRow()

    XCTAssertEqual(
      shape(of: row.body),
      "VStack<TupleView<(HStack<TupleView<(Text, ModifiedContent<ModifiedContent<ModifiedContent<"
        + "ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<ModifiedContent<"
        + "ModifiedContent<ModifiedContent<ModifiedContent<TextField<Text>, "
        + "TextFieldStyleModifier<PlainTextFieldStyle>>, _ForegroundStyleModifier<Color>>, "
        + "_PaddingLayout>, _PaddingLayout>, _InsettableBackgroundShapeModifier<Color, "
        + "RoundedRectangle>>, _FrameLayout>, FocusStateBindingModifier<Bool>>, "
        + "AccessibilityAttachmentModifier>, _AppearanceActionModifier>, OnSubmitModifier>, "
        + "OnCommandModifier>, Text)>>, Text)>>",
    )
  }

  /// The row opens with the caret already in it: `Custom…` is meant to be followed by typing, not
  /// by a click. `@FocusState` only reaches the keyboard through a view SwiftUI has actually
  /// rendered, so this asks the real window who holds the keyboard, and gets the field's own
  /// editor rather than the window itself. MeetingEntryRow.swift:41:31.
  func testOpeningTheRowPutsTheKeyboardInTheField() throws {
    let (row, _, _, _) = try makeRow()
    let (hosting, window) = hostInWindow(row.frame(width: 300))
    let field = try XCTUnwrap(findTextField(in: hosting), "no text field found for the meeting entry row")

    waitForKeyboard(in: field, of: window)

    let holder = try XCTUnwrap(
      window.firstResponder as? NSView,
      "the window itself still holds the keyboard; the row never asked for it",
    )
    XCTAssertTrue(holder.isDescendant(of: field), "the keyboard went somewhere other than the meeting field")
  }

  /// Pressing Return in the field is what actually calls `submit(text)` — not merely `submit()`
  /// called directly, which every other test in this file does. The field's own text is empty when
  /// read outside a hosted view, so firing this wiring refuses and alerts rather than starting a
  /// meeting — still the one observable difference the mutant erases. MeetingEntryRow.swift:42:19.
  func testSubmittingFromTheFieldRefusesItsEmptyTextAndAlerts() throws {
    let (row, _, model, refusals) = try makeRow()
    let onSubmit = try XCTUnwrap(try child("action", of: try layer(.submit, of: row)) as? () -> Void)

    onSubmit()

    XCTAssertEqual(refusals.count, 1)
    XCTAssertTrue(model.isEnteringMeeting, "a refusal must leave the field open")
  }

  /// Escape is the field's own Cancel command — closing it without starting a meeting.
  /// MeetingEntryRow.swift:43:50.
  func testExitCommandClosesTheFieldWithoutStartingAMeeting() throws {
    let (row, transport, model, _) = try makeRow()
    let exit = try layer(.exitCommand, of: row)
    let cancel = try XCTUnwrap(
      try child("action", of: try child("action", of: exit)) as? () -> Void,
      "the exit command has nothing to run",
    )

    cancel()

    XCTAssertFalse(model.isEnteringMeeting, "Escape closed the field that was open")
    XCTAssertEqual(transport.requests.count, 0, "Escape must not start a meeting")
  }

  // MARK: Private

  /// Where each modifier sits in `field`'s stack, counted from the innermost.
  /// `LunchEntryRowTests.testBodyIsTheRuleUnderALabeledFieldFlankedByItsUnitLabels` pins the same
  /// field shape; this only names the two positions the wiring tests read.
  private enum Layer: Int {
    case submit = 9
    case exitCommand = 10
  }

  /// A counter the row can report a refusal into, so the beep is observable.
  private final class RefusalLog {
    var count = 0
  }

  /// A meeting can be started from any state, so the row opens over any phase ground; work's is
  /// the one it opens over while a meeting is already running.
  private let scheme = Palette.scheme(for: .work)

  private func makeRow() throws -> (MeetingEntryRow, StubTransport, WindowModel, RefusalLog) {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    let model = environment.windowModel
    model.beginEntry(.meeting)
    let refusals = RefusalLog()
    let row = MeetingEntryRow(client: environment.client, model: model) { refusals.count += 1 }
    return (row, transport, model, refusals)
  }

  private func layer(_ layer: Layer, of row: MeetingEntryRow) throws -> Any {
    try part(layer.rawValue, of: modifierLayers(of: row.field))
  }

  private func waitForRequest(_ transport: StubTransport) throws {
    let deadline = Date().addingTimeInterval(2)
    while transport.requests.isEmpty, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

import AppKit
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class LunchEntryRowTests: XCTestCase {

  // MARK: Internal

  func testAWholeNumberOfMinutesStartsLunchAndClosesTheField() throws {
    let (row, transport, model, refusals) = try makeRow()
    row.submit("45")

    XCTAssertEqual(refusals.count, 0, "a valid length must not beep")
    XCTAssertFalse(model.isEnteringLunch, "the field closes once it is answered")
    try waitForRequest(transport)
    XCTAssertEqual(
      transport.requests,
      [StubTransport.Request(method: "POST", path: "/v1/timer/lunch", body: #"{"minutes":45}"#)],
    )
  }

  /// A refusal keeps the field open with the text intact: the user mistyped, and retyping from
  /// scratch is a worse answer than correcting.
  func testARefusedLengthBeepsAndLeavesTheFieldOpen() throws {
    for entry in ["", "  ", "0", "-1", "abc", "1.5", "90m", "99999"] {
      let (row, transport, model, refusals) = try makeRow()
      row.submit(entry)
      XCTAssertEqual(refusals.count, 1, entry)
      XCTAssertTrue(model.isEnteringLunch, entry)
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
    _ = LunchEntryRow(client: environment.client, model: environment.windowModel).body
  }

  /// The same call the snooze and meeting fields make, for the same reason: a system-drawn
  /// field takes the system appearance's background while the text on it stays this window's
  /// ink, which is black on black in Dark Mode. Painted in the app's own paper, the colour is
  /// there in the pixels (throwntom-bxd.3).
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

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed: the rule
  /// under a row that labels the field on both sides. A statement that stops being built — either
  /// label, the row that lays them out, or the stack around it — changes this string.
  /// LunchEntryRow.swift:19:5, :20:7, :21:9, :23:9.
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
  /// editor rather than the window itself. LunchEntryRow.swift:42:31.
  func testOpeningTheRowPutsTheKeyboardInTheField() throws {
    let (row, _, _, _) = try makeRow()
    let (hosting, window) = hostInWindow(row.frame(width: 300))
    let field = try XCTUnwrap(findTextField(in: hosting), "no text field found for the lunch entry row")

    waitForKeyboard(in: field, of: window)

    let holder = try XCTUnwrap(
      window.firstResponder as? NSView,
      "the window itself still holds the keyboard; the row never asked for it",
    )
    XCTAssertTrue(holder.isDescendant(of: field), "the keyboard went somewhere other than the lunch field")
  }

  /// Pressing Return in the field is what actually calls `submit(text)` — not merely `submit()`
  /// called directly, which every other test in this file does. The field's own text is empty when
  /// read outside a hosted view, so firing this wiring refuses and alerts rather than starting
  /// lunch — still the one observable difference the mutant erases. LunchEntryRow.swift:43:19.
  func testSubmittingFromTheFieldRefusesItsEmptyTextAndAlerts() throws {
    let (row, _, model, refusals) = try makeRow()
    let onSubmit = try XCTUnwrap(try child("action", of: try layer(.submit, of: row)) as? () -> Void)

    onSubmit()

    XCTAssertEqual(refusals.count, 1)
    XCTAssertTrue(model.isEnteringLunch, "a refusal must leave the field open")
  }

  /// Escape is the field's own Cancel command — closing it without starting lunch.
  /// LunchEntryRow.swift:44:48.
  func testExitCommandClosesTheFieldWithoutStartingLunch() throws {
    let (row, transport, model, _) = try makeRow()
    let exit = try layer(.exitCommand, of: row)
    let cancel = try XCTUnwrap(
      try child("action", of: try child("action", of: exit)) as? () -> Void,
      "the exit command has nothing to run",
    )

    cancel()

    XCTAssertFalse(model.isEnteringLunch, "Escape closed the field that was open")
    XCTAssertEqual(transport.requests.count, 0, "Escape must not start lunch")
  }

  // MARK: Private

  /// Where each modifier sits in `field`'s stack, counted from the innermost.
  /// `testBodyIsTheRuleUnderALabeledFieldFlankedByItsUnitLabels` pins the field's own shape;
  /// this only names the two positions the wiring tests read.
  private enum Layer: Int {
    case submit = 9
    case exitCommand = 10
  }

  /// A counter the row can report a refusal into, so the beep is observable.
  private final class RefusalLog {
    var count = 0
  }

  /// Lunch can be started from any state, so the row opens over any phase ground; work's is the
  /// one it opens over most often.
  private let scheme = Palette.scheme(for: .work)

  private func makeRow() throws -> (LunchEntryRow, StubTransport, WindowModel, RefusalLog) {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    let model = environment.windowModel
    model.beginEntry(.lunch)
    let refusals = RefusalLog()
    let row = LunchEntryRow(client: environment.client, model: model) { refusals.count += 1 }
    return (row, transport, model, refusals)
  }

  private func layer(_ layer: Layer, of row: LunchEntryRow) throws -> Any {
    try part(layer.rawValue, of: modifierLayers(of: row.field))
  }

  private func waitForRequest(_ transport: StubTransport) throws {
    let deadline = Date().addingTimeInterval(2)
    while transport.requests.isEmpty, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class CommandChipsTests: XCTestCase {

  // MARK: Internal

  func testEveryWindowCommandGetsASecondaryChip() throws {
    let chips = try makeChips()

    XCTAssertEqual(chips.menu.items.map(\.action), [.tasks, .stats, .shortcuts, .openConfig])
    for item in chips.menu.items {
      let chip = chips.chip(for: item)
      XCTAssertEqual(chip.title, item.title)
      XCTAssertEqual(chip.hint, item.action.shortcutHint)
      XCTAssertEqual(chip.style, ChipStyle.style(primary: false, scheme: chips.scheme), "\(item.action)")
    }
  }

  func testTappingAChipRunsItsCommand() throws {
    let chips = try makeChips()
    let model = chips.environment.windowModel

    chips.chip(for: try item(chips, .tasks)).action()
    XCTAssertEqual(model.panel, .tasks)
    chips.chip(for: try item(chips, .stats)).action()
    XCTAssertEqual(model.panel, .stats)
    chips.chip(for: try item(chips, .stats)).action()
    XCTAssertNil(model.panel, "a second tap closes the panel it opened")

    chips.chip(for: try item(chips, .shortcuts)).action()
    XCTAssertTrue(model.showsShortcuts)
  }

  func testDispatchIsWhatTheMenuBarAlreadyDoes() {
    let model = WindowModel()

    ViewActionDispatch.show(.tasks, in: model)
    XCTAssertEqual(model.panel, .tasks)
    ViewActionDispatch.show(.shortcuts, in: model)
    XCTAssertTrue(model.showsShortcuts)
  }

  func testTheCheatSheetChipIsDeadWhileItsSheetIsOpen() throws {
    let chips = try makeChips()
    chips.environment.windowModel.showsShortcuts = true

    // The row draws `.disabled(!item.isEnabled)`, so this is the state that reaches the chip.
    XCTAssertFalse(try XCTUnwrap(chips.menu.item(for: .shortcuts)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(chips.menu.item(for: .tasks)).isEnabled)
    _ = chips.body
  }

  func testChipRowBodyBuilds() throws {
    _ = try makeChips().body
  }

  /// `chip(for:)` on its own (already exercised above) never proves the row's `ForEach` is what
  /// actually walks `menu.items` and builds each one through `chip(for:).disabled(...)`, rather
  /// than through nothing.
  func testTheRowsForEachWalksEveryItemAndBuildsItThroughChipFor() throws {
    let chips = try makeChips()
    let forEach = try child("content", of: chips.body)
    XCTAssertTrue(shape(of: forEach).hasPrefix("ForEach<"), shape(of: forEach))

    // Spelled as a typealias rather than inline: a multi-line generic argument list's trailing
    // comma (required by this repo's own formatter) doesn't parse on every Swift toolchain this
    // project builds with, and a single line here would run well past the column limit.
    typealias DisabledChip = ModifiedContent<Chip, _EnvironmentKeyTransformModifier<Bool>>
    let closure = try XCTUnwrap(
      try child("content", of: forEach) as? (MenuItem<ViewAction>) -> DisabledChip,
      "the row is no longer built through chip(for:).disabled(...)",
    )
    let built = closure(try item(chips, .tasks))
    XCTAssertEqual(shape(of: try content(of: built)), "Chip")
  }

  // MARK: Private

  private func makeChips() throws -> CommandChips {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return CommandChips(environment: environment, scheme: Palette.scheme(for: .work))
  }

  private func item(_ chips: CommandChips, _ action: ViewAction) throws -> MenuItem<ViewAction> {
    try XCTUnwrap(chips.menu.item(for: action))
  }

}

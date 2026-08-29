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

  func testChipRowBodyBuilds() throws {
    _ = try makeChips().body
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

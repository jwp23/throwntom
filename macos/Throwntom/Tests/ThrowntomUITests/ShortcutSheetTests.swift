import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutSheetTests: XCTestCase {
  func testEverySectionListsOnlyItemsWithShortcuts() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let sections = ShortcutList.sections(for: environment)
    XCTAssertEqual(sections.map(\.name), ["Timer", "View", "Tasks", "App"])
    XCTAssertEqual(sections[0].entries.map(\.hint), ["⌘R", "⏎", "⌘P", "⌘⇧S"], "Skip Today and New Cycle have none")
    XCTAssertEqual(sections[1].entries.map(\.hint), ["⌘T", "⌘⇧D", "⌘/"])
    XCTAssertEqual(sections[2].entries.map(\.hint), ["⌘N", "⌘⏎", "⌘⌫", "⌘F", "⌥↑", "⌥↓"])
    XCTAssertEqual(
      sections[3].entries,
      [.init(title: "Open Config File…", hint: "⌘,"), .init(title: "Quit Throwntom", hint: "⌘Q")],
    )
    XCTAssertTrue(sections.flatMap(\.entries).allSatisfy { !$0.hint.isEmpty })
  }

  func testSheetBodyBuilds() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    _ = ShortcutSheet(environment: environment).body
  }
}

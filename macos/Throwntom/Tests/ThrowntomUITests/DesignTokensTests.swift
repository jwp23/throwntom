import XCTest
@testable import ThrowntomUI

/// DESIGN.md is the documented palette; Palette.swift is the running one. They must agree byte for byte.
final class DesignTokensTests: XCTestCase {

  // MARK: Internal

  func testDesignTokensMatchPalette() throws {
    let tokens = try designTokens()
    XCTAssertEqual(tokens["macos-ink"], Palette.ink.hex)
    XCTAssertEqual(tokens["macos-cream"], Palette.cream.hex)
    XCTAssertEqual(tokens["macos-outline"], Palette.outline.hex)
    for (name, scheme) in Palette.schemes {
      XCTAssertEqual(tokens[name], scheme.ground.hex, name)
      XCTAssertEqual(tokens["\(name)-chip"], scheme.secondaryChip.hex, "\(name)-chip")
    }
  }

  // MARK: Private

  /// `name: "#RRGGBB"` lines from the YAML front matter, keyed by name.
  private func designTokens() throws -> [String: String] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("DESIGN.md"), encoding: .utf8)
    let frontMatter = text.components(separatedBy: "\n---\n").first ?? ""
    var tokens = [String: String]()
    for match in frontMatter.matches(of: #/^\s*([a-z0-9-]+):\s*"(#[0-9A-Fa-f]{6})"/#.anchorsMatchLineEndings()) {
      tokens[String(match.1)] = String(match.2).uppercased()
    }
    return tokens
  }

}

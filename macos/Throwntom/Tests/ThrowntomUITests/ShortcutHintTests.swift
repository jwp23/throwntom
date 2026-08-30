import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ShortcutHintTests: XCTestCase {
  func testHintsAreBodySizedMonospacedAndNotLightweight() {
    XCTAssertEqual(ShortcutHint.font, Font.body.monospaced().weight(.medium))
  }

  func testHintBodyBuilds() {
    _ = ShortcutHint(TaskHints.line).body
  }
}

import XCTest
@testable import ThrowntomUI

@MainActor
final class SnoozedLineTests: XCTestCase {

  func testTheLineBuildsCountingAndStill() {
    _ = SnoozedLine(note: "Snoozed · 09:12 left", remaining: "09:12").body
    _ = SnoozedLine(note: "Snoozed · 09:12 left", remaining: nil).body
  }

}

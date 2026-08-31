import SwiftUI
import XCTest
@testable import ThrowntomUI

/// throwntom-jnv, and the decision the live countdown turns on. The window has two lines whose
/// number moves every second — the headline and the snoozed line — and both are read as a steady
/// name with a value under it rather than as text that is quietly different each time VoiceOver
/// lands on it.
@MainActor
final class LiveValueTests: XCTestCase {

  /// `.updatesFrequently` tells VoiceOver the value moves on its own, so a reader gets a fresh one
  /// when they ask rather than whatever was true when they last passed through. What it
  /// deliberately is not is an announcement: a value rewritten every second, spoken, would be
  /// VoiceOver interrupting itself continuously.
  func testACountingLineTellsVoiceOverItsValueGoesStale() {
    XCTAssertTrue(LiveValue(label: "Pomodoro", value: "24:59").traits.contains(.updatesFrequently))
  }

  /// A still line must not claim to move: the trait costs a re-read every time VoiceOver lands on
  /// it, and an idle screen has nothing new to say.
  func testAStillLineClaimsNothingOfTheSort() {
    XCTAssertFalse(LiveValue(label: "Idle", value: nil).traits.contains(.updatesFrequently))
  }

  /// The name has to hold still while the number moves. A label that carried the countdown would be
  /// a different label every second, and VoiceOver reads a changed label as a *new element* rather
  /// than as the same one counting down — which is why the trait alone does not fix it.
  func testTheMovingPartIsTheValueAndNeverTheLabel() {
    let counting = LiveValue(label: "Pomodoro. Next: Short break 5 min", value: "24:59")

    XCTAssertFalse(counting.label.contains("24:59"), counting.label)
    XCTAssertEqual(counting.value, "24:59")
  }

  /// An empty value is a value the element does not have. A line with nothing counting is a name
  /// and nothing else.
  func testALineWithNothingCountingClaimsNoValueAtAll() {
    XCTAssertNil(LiveValue(label: "Timer service stopped", value: nil).value)
  }

}

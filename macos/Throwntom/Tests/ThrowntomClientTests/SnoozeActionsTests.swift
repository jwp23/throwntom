import XCTest
@testable import ThrowntomClient

final class SnoozeActionsTests: XCTestCase {

  func testPresetsAreTheFourOfferedDurations() {
    XCTAssertEqual(SnoozeActions.presets, [10, 15, 30, 60])
  }

  func testTheDefaultPresetIsTheOneAPlainSnoozeUses() {
    XCTAssertEqual(SnoozeActions.defaultMinutes, TimerActions.defaultSnoozeMinutes)
    XCTAssertTrue(SnoozeActions.presets.contains(SnoozeActions.defaultMinutes))
  }

  func testMinutesReadAsMinutesUntilTheyMakeAWholeHour() {
    XCTAssertEqual(SnoozeAction.snooze(minutes: 10).title, "10 minutes")
    XCTAssertEqual(SnoozeAction.snooze(minutes: 30).title, "30 minutes")
    XCTAssertEqual(SnoozeAction.snooze(minutes: 60).title, "1 hour")
    XCTAssertEqual(SnoozeAction.snooze(minutes: 120).title, "2 hours")
    XCTAssertEqual(SnoozeAction.snooze(minutes: 1).title, "1 minute")
  }

  func testCustomAndCancelAreNamedForWhatTheyDo() {
    XCTAssertEqual(SnoozeAction.custom.title, "Custom…")
    XCTAssertEqual(SnoozeAction.cancel.title, "Cancel Snooze")
  }

  func testABareNumberIsMinutes() {
    XCTAssertEqual(SnoozeDraft.minutes(from: "45"), 45)
    XCTAssertEqual(SnoozeDraft.minutes(from: " 45 "), 45)
  }

  func testNonPositiveAndUnreadableEntriesAreRefused() {
    for entry in ["0", "-5", "", "   ", "abc", "1.5", "10m"] {
      XCTAssertNil(SnoozeDraft.minutes(from: entry), entry)
    }
  }

  func testAnAbsurdlyLongSnoozeIsRefused() {
    // A whole day of silence is a typo, not an intention; the daemon would take it.
    XCTAssertEqual(SnoozeDraft.minutes(from: "1440"), 1440)
    XCTAssertNil(SnoozeDraft.minutes(from: "1441"))
  }

}

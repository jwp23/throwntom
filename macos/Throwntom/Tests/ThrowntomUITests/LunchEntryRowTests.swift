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

  // MARK: Private

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

  private func waitForRequest(_ transport: StubTransport) throws {
    let deadline = Date().addingTimeInterval(2)
    while transport.requests.isEmpty, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// That the sheet *draws* what can fire right now, rather than that `ShortcutList` merely worked it
/// out.
///
/// `ShortcutSheetTests` asserts the entries and never runs the body, so with it green the sheet can
/// go on painting every row at full strength while the model beside it says half of them cannot
/// fire — which is this project's dominant defect: a test that pins a value the view ignores. This
/// is the dimming counterpart of `WindowFontRenderingTests` and works the same way, by rendering
/// twice and measuring the difference, so everything the two drawings share — the same titles,
/// hints, conditions, spacing and Done button — cancels.
///
/// The two differ in one thing: whether there is a timer service to send to. With one, most of the
/// list can fire; without one, only the local commands can. Ink separates them, because a dimmed
/// row paints less of it.
@MainActor
final class ShortcutSheetRenderingTests: XCTestCase {

  // MARK: Internal

  func testTheSheetDrawsLessInkWhereLessCanFire() async throws {
    let running = try await runningEnvironment()
    defer { running.client.stop() }
    let stopped = try stoppedEnvironment()

    let withADaemon = try ink(of: sheet(running))
    let withNone = try ink(of: sheet(stopped))

    XCTAssertGreaterThan(withADaemon, 0, "nothing was drawn, so there is nothing to compare")
    XCTAssertLessThan(
      withNone,
      withADaemon,
      "the sheet draws the same ink with no daemon as with one, so it is not showing what can fire",
    )
  }

  /// The control. Two drawings of one sheet must be identical, or the comparison above could be
  /// reading rendering noise rather than the dim.
  func testTwoDrawingsOfOneSheetAreIdentical() throws {
    let environment = try stoppedEnvironment()

    XCTAssertEqual(try ink(of: sheet(environment)), try ink(of: sheet(environment)))
  }

  // MARK: Private

  /// A stop the user asked for, which is the one way to reach a service-down screen with no dialling
  /// having to fail first.
  private func stoppedEnvironment() throws -> AppEnvironment {
    AppEnvironment(transport: try StubTransport(states: []), intents: MemoryServiceIntentStore(.stopped))
  }

  /// A live daemon part-way through a pomodoro: Pause and Skip can fire, Start and Confirm cannot.
  private func runningEnvironment() async throws -> AppEnvironment {
    let environment = AppEnvironment(transport: try StubTransport(states: [makeState(phase: .work)]))
    environment.start()
    try await waitUntil { environment.client.state != nil }
    return environment
  }

  /// The sheet at a fixed width, so two drawings of it are the same size and comparable.
  private func sheet(_ environment: AppEnvironment) -> some View {
    ShortcutSheet(environment: environment).frame(width: 480)
  }

  /// How much the drawing paints, summed over every pixel's alpha. A row drawn at reduced opacity
  /// contributes proportionally less, and anything both drawings share contributes the same to
  /// each.
  private func ink(of view: some View) throws -> Double {
    let rep = try AppearanceRender.bitmap(view, appearance: .aqua, scheme: .light)
    var total = 0.0
    for y in 0 ..< rep.pixelsHigh {
      for x in 0 ..< rep.pixelsWide {
        total += Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
      }
    }
    return total
  }

}

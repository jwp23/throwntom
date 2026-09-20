import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What launching the app does, and what it is made of. Built around wiring handed in rather than
/// the app's own `init()`: that one builds `AppEnvironment.live()`, whose presenter and authorizer
/// reach for the real notification centre, which refuses a process without an app bundle.
@MainActor
final class ThrowntomAppTests: XCTestCase {

  // MARK: Internal

  /// Launching is where the delegate is claimed, before any banner can be posted: macOS hands a
  /// reminder's answer to the delegate and to nothing else.
  func testLaunchingStartsTheReminderResponder() throws {
    let presenter = StubReminderPresenter()
    let environment = try makeEnvironment(presenter: presenter)
    defer { shutDown(environment) }

    _ = ThrowntomApp(environment: environment)

    XCTAssertTrue(presenter.claimedDelegate === environment.responder)
  }

  /// The daemon connection and the clock start at launch, not in a view's `onAppear`: the window's
  /// content only appears once SwiftUI has rendered it, and it may never be opened at all.
  func testLaunchingStartsTheDaemonConnection() async throws {
    let environment = try makeEnvironment(
      presenter: StubReminderPresenter(),
      states: [makeState(phase: .work)],
    )
    defer { shutDown(environment) }

    _ = ThrowntomApp(environment: environment)

    try await waitUntil { environment.client.connection == .connected }
    XCTAssertEqual(environment.client.state?.state, .work)
  }

  /// The app is its scenes and nothing else — the one place the whole window and its menus are
  /// hung off the app, read back out of `body`'s own type (see `ThrowntomScenesTests`).
  func testTheAppIsTheThrowntomScenes() throws {
    let environment = try makeEnvironment(presenter: StubReminderPresenter())
    defer { shutDown(environment) }

    let app = ThrowntomApp(environment: environment)

    XCTAssertEqual(shape(of: app.body), "ThrowntomScenes")
  }

  // MARK: Private

  private func makeEnvironment(
    presenter: StubReminderPresenter,
    states: [DaemonState] = [],
  ) throws -> AppEnvironment {
    AppEnvironment(
      transport: try StubTransport(states: states),
      authorizer: StubAuthorizer(),
      presenter: presenter,
    )
  }

  private func shutDown(_ environment: AppEnvironment) {
    environment.client.stop()
    environment.ticker.stop()
  }

}

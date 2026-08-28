import SwiftUI
import UserNotifications
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// The popover is 280 points wide and its captions are sentences, not labels. A caption that
/// truncates rather than wraps hides the daemon error or the permission warning that is its whole
/// reason to exist, and nothing else in the app reports either of them.
@MainActor
final class PopoverCaptionLayoutTests: XCTestCase {

  // MARK: Internal

  func testADaemonErrorPastTwoLinesStillMakesThePopoverTaller() async throws {
    let twoLines = try await popover(reportingDaemonError: Self.twoLineError)
    let manyLines = try await popover(reportingDaemonError: Self.manyLineError)

    XCTAssertGreaterThan(height(of: manyLines), height(of: twoLines))
  }

  func testAPermissionWarningPastTwoLinesStillMakesThePopoverTaller() async throws {
    let twoLines = try await popover(reportingRefusal: refusal(saying: Self.twoLineError))
    let manyLines = try await popover(reportingRefusal: refusal(saying: Self.manyLineError))

    XCTAssertGreaterThan(height(of: manyLines), height(of: twoLines))
  }

  // MARK: Private

  /// Two lines' worth of daemon error at the popover's width.
  private static let twoLineError = """
    connect: no such file or directory: the timer daemon is not listening on its socket
    """

  /// The same failure with the socket path and the retry the client reports with it, which is
  /// what a real transport error looks like once the daemon has been down for a while.
  private static let manyLineError = """
    connect: no such file or directory: the timer daemon is not listening on its socket at \
    /Users/throwntom/.config/throwntom/daemon.sock, and the launch agent that starts it has \
    been asked to run and has not answered
    """

  private func refusal(saying description: String) -> NSError {
    NSError(domain: UNErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: description])
  }

  private func popover(reportingDaemonError message: String) async throws -> PopoverView {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport(message: message))
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.unresolvedError?.contains(message) == true }
    return makePopover(environment)
  }

  private func popover(reportingRefusal refusal: NSError) async throws -> PopoverView {
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      authorizer: StubAuthorizer(refusal: refusal),
    )
    await environment.responder.requestAuthorization()
    return makePopover(environment)
  }

  private func makePopover(_ environment: AppEnvironment) -> PopoverView {
    PopoverView(
      client: environment.client,
      ticker: environment.ticker,
      registrar: environment.registrar,
      responder: environment.responder,
    )
  }

  private func height(of view: some View) -> CGFloat {
    NSHostingView(rootView: view).fittingSize.height
  }

}

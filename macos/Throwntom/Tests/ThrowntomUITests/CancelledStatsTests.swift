import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - StallingTransport

/// A transport whose every request hangs until the calling task is cancelled, which is how a
/// cancelled request really ends: the socket resumes the suspended operation by throwing, and
/// `Task.sleep` throws the same `CancellationError` the socket does.
// Holds no mutable state; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class StallingTransport: DaemonTransport, @unchecked Sendable {

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    try await Task.sleep(for: .seconds(60))
    return HTTPResponse(status: 200, headers: [:], body: Data())
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish() }
  }

}

// MARK: - CancelledStatsTests

/// Closing the panel cancels the fetch it opened, and a fetch the panel itself cancelled is not
/// stats that failed to load (throwntom-esk).
@MainActor
final class CancelledStatsTests: XCTestCase {

  func testAPanelClosedMidFetchDoesNotReportAFailure() async {
    let environment = AppEnvironment(transport: StallingTransport())
    let loader = StatsLoader()

    let inFlight = Task { await loader.load(from: environment.client) }
    inFlight.cancel()
    await inFlight.value

    XCTAssertEqual(loader.outcome, .loading)
  }

  /// The guard must not swallow real failures with the cancelled ones: an uncancelled failure
  /// still has to reach the panel, or the fix would read as passing by never reporting anything.
  func testAnUncancelledFailureStillReachesThePanel() async {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    let loader = StatsLoader()

    await loader.load(from: environment.client)

    XCTAssertEqual(
      loader.outcome,
      .failed("Stats unavailable: " + DaemonError.transport("no daemon").userMessage),
    )
  }

}

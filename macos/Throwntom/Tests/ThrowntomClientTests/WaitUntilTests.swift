import XCTest
@testable import ThrowntomClient

/// `waitUntil` is the suite's only way of waiting on something asynchronous, so what it says
/// when it gives up is what a whole class of failures looks like. A bare `CancellationError`
/// naming neither the condition nor the wait made throwntom-486 look like three separate bugs.
@MainActor
final class WaitUntilTests: XCTestCase {

  // MARK: Internal

  /// A CI log carries the message, not the source line, so the message has to carry both the
  /// condition and the place that was waiting for it.
  func testATimedOutWaitNamesTheConditionAndTheCallSite() async {
    let failure = await pollUntil("the daemon to answer", timeout: 0.05) { false }

    let description = failure?.description ?? Self.nothingReported
    XCTAssertTrue(description.contains("the daemon to answer"), description)
    XCTAssertTrue(description.contains("WaitUntilTests.swift"), description)
    XCTAssertTrue(description.contains("timed out"), description)
  }

  /// The reported symptom: an overrunning test cancels the wait's sleep, and the resulting
  /// `CancellationError` was attributed to whichever source line happened to be sleeping.
  func testACancelledWaitIsReportedAsThisWaitNotAsACancellationError() async throws {
    let wait = Task { @MainActor in
      await pollUntil("a condition that never holds", timeout: 60) { false }
    }
    try await Task.sleep(for: .milliseconds(50))
    wait.cancel()

    let description = await wait.value?.description ?? Self.nothingReported
    XCTAssertTrue(description.contains("a condition that never holds"), description)
    XCTAssertTrue(description.contains("cancelled"), description)
  }

  /// The ordinary path: a condition that holds is not a failure at all.
  func testAConditionThatHoldsReportsNothing() async {
    let failure = await pollUntil("a condition that already holds", timeout: 5) { true }

    XCTAssertNil(failure)
  }

  // MARK: Private

  /// Stands in for the failure a wait did not report, so an assertion message says that rather
  /// than "nil".
  private static let nothingReported = "no failure reported"

}

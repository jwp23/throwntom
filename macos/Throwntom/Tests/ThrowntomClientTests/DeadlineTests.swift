import XCTest
@testable import ThrowntomClient

/// `withDeadline` exists for the case its callers cannot cover themselves: work that will never
/// finish and will not answer cancellation, which is what a socket call looks like if whatever
/// resumes its continuation ever stops doing so.
///
/// Every wait here is bounded. A call that never ends has to fail its test on a deadline of the
/// test's own, because a test that waited for it instead would hang the whole suite.
final class DeadlineTests: XCTestCase {

  // MARK: Internal

  /// The deadline the callers are promised is the deadline they get, whatever the work does.
  func testTheDeadlineFailsTheCallWhenTheWorkNeverFinishes() async {
    let timeout = Duration.milliseconds(200)
    let failed = expectation(description: "the call to fail on its deadline")
    let call = Task {
      do {
        try await withDeadline(timeout) { await Self.suspendsForever() }
        XCTFail("the call returned although its work never finished")
      } catch {
        XCTAssertEqual(error as? DaemonError, .timedOut(after: timeout))
      }
      failed.fulfill()
    }
    defer { call.cancel() }

    await fulfillment(of: [failed], timeout: 2)
  }

  /// Cancelling is the other way a caller stops waiting, and it is bounded for the same reason.
  func testCancellingTheCallerEndsTheCallWhenTheWorkNeverFinishes() async {
    let ended = expectation(description: "the call to end as cancelled")
    let call = Task {
      do {
        try await withDeadline(.seconds(30)) { await Self.suspendsForever() }
        XCTFail("the call returned although it was cancelled")
      } catch {
        XCTAssertTrue(error is CancellationError, "the cancelled call failed with \(error)")
      }
      ended.fulfill()
    }

    // Cancel once the call is waiting rather than before it starts, so the test covers the wait.
    try? await Task.sleep(for: .milliseconds(100))
    call.cancel()

    await fulfillment(of: [ended], timeout: 2)
  }

  /// Work the call walks away from is still asked to stop, so a deadline does not leave the
  /// socket behind it running.
  func testAbandonedWorkIsCancelled() async {
    let cancelled = expectation(description: "the abandoned work to be cancelled")
    do {
      try await withDeadline(.milliseconds(100)) {
        do {
          try await Task.sleep(for: .seconds(30))
        } catch {
          cancelled.fulfill()
          throw error
        }
      }
      XCTFail("the call returned although its work had not finished")
    } catch {
      XCTAssertEqual(error as? DaemonError, .timedOut(after: .milliseconds(100)))
    }

    await fulfillment(of: [cancelled], timeout: 2)
  }

  func testWorkThatBeatsItsDeadlineReturnsItsValue() async throws {
    let value = try await withDeadline(.seconds(5)) { "answered" }

    XCTAssertEqual(value, "answered")
  }

  /// The deadline decides only when the work has not: a failure of the work's own is what the
  /// caller hears about, not a timeout standing in for it.
  func testWorkThatFailsReportsItsOwnError() async {
    do {
      try await withDeadline(.seconds(5)) { try Self.refuse() }
      XCTFail("the failing work returned a value")
    } catch {
      XCTAssertEqual(error as? DaemonError, .transport("refused"))
    }
  }

  // MARK: Private

  /// Work that will never finish and does not answer cancellation: a continuation nothing ever
  /// resumes. Unsafe rather than checked deliberately — a checked continuation reports the leak
  /// on the console when it is released, and this one is leaked on purpose.
  private static func suspendsForever() async {
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
  }

  /// Work that fails on its own terms, well inside its deadline.
  private static func refuse() throws {
    throw DaemonError.transport("refused")
  }

}

import XCTest
@testable import ThrowntomClient

// MARK: - ReconnectBackoffTests

final class ReconnectBackoffTests: XCTestCase {

  // MARK: Internal

  func testEscalatesThroughTheDelaysAndHoldsAtTheLast() {
    var backoff = Self.backoff(registerEvery: 99)

    XCTAssertEqual(
      Self.delays(of: &backoff, over: 6),
      [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8), .seconds(8)],
    )
  }

  /// The point of the whole type: the dial after registration checks launchd's work promptly
  /// instead of waiting out the escalated delay the outage had already reached.
  func testRegisteringTheAgentRewindsToTheShortestDelay() {
    var backoff = Self.backoff(registerEvery: 3)
    var seen = [Duration]()
    for _ in 1...5 {
      backoff.recordFailure()
      if backoff.shouldRegisterAgent {
        backoff.agentRegistered()
      }
      seen.append(backoff.delay)
    }

    XCTAssertEqual(seen, [.seconds(1), .seconds(2), .seconds(1), .seconds(2), .seconds(4)])
  }

  /// Rewinding on every registration would re-register every second or so for as long as the
  /// outage lasted, which asks launchd to restart a daemon that may already be starting.
  func testOnlyTheFirstRegistrationOfAnOutageRewinds() {
    var backoff = Self.backoff(registerEvery: 3)
    var seen = [Duration]()
    for _ in 1...6 {
      backoff.recordFailure()
      if backoff.shouldRegisterAgent {
        backoff.agentRegistered()
      }
      seen.append(backoff.delay)
    }

    XCTAssertEqual(seen.last, .seconds(8), "the sixth failure re-registers but keeps escalating")
    XCTAssertTrue(backoff.hasAskedLaunchdToStart)
  }

  func testRegistersOnEveryNthFailure() {
    var backoff = Self.backoff(registerEvery: 3)
    var registering = [Bool]()
    for _ in 1...7 {
      backoff.recordFailure()
      registering.append(backoff.shouldRegisterAgent)
    }

    XCTAssertEqual(registering, [false, false, true, false, false, true, false])
  }

  func testAFrameFromTheDaemonStartsTheNextOutageFromScratch() {
    var backoff = Self.backoff(registerEvery: 3)
    for _ in 1...4 {
      backoff.recordFailure()
    }
    backoff.reset()
    backoff.recordFailure()

    XCTAssertEqual(backoff.failures, 1)
    XCTAssertEqual(backoff.delay, .seconds(1))
    XCTAssertFalse(backoff.hasAskedLaunchdToStart)
  }

  // MARK: Private

  private static func backoff(registerEvery: Int) -> ReconnectBackoff {
    ReconnectBackoff(delays: [.seconds(1), .seconds(2), .seconds(4), .seconds(8)], registerEvery: registerEvery)
  }

  private static func delays(of backoff: inout ReconnectBackoff, over failures: Int) -> [Duration] {
    (1...failures).map { _ in
      backoff.recordFailure()
      return backoff.delay
    }
  }

}

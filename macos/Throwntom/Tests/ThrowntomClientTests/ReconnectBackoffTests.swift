import XCTest
@testable import ThrowntomClient

// MARK: - ReconnectBackoffTests

final class ReconnectBackoffTests: XCTestCase {

  // MARK: Internal

  func testEscalatesThroughTheDelaysAndHoldsAtTheLast() async {
    var backoff = Self.backoff(registerEvery: 99)

    let seen = await Self.delays(of: &backoff, over: 6)

    XCTAssertEqual(seen, [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8), .seconds(8)])
  }

  /// The point of the rewind: the dial after registration checks launchd's work promptly
  /// instead of waiting out the escalated delay the outage had already reached.
  func testRegisteringTheAgentRewindsToTheShortestDelay() async {
    var backoff = Self.backoff(registerEvery: 3)

    let seen = await Self.delays(of: &backoff, over: 5)

    XCTAssertEqual(seen, [.seconds(1), .seconds(2), .seconds(1), .seconds(2), .seconds(4)])
  }

  /// Registering is unregister-then-register, so asking again during the same outage boots out
  /// the daemon the first ask started, and launchd's 10 s minimum runtime throttles the respawn.
  func testTheAgentIsRegisteredAtMostOncePerOutage() async {
    var backoff = Self.backoff(registerEvery: 3)
    var registrations = 0

    _ = await Self.delays(of: &backoff, over: 9) {
      registrations += 1
      return true
    }

    XCTAssertEqual(registrations, 1, "the sixth and ninth failures must not ask launchd again")
    XCTAssertEqual(backoff.delay, .seconds(8), "and the outage keeps escalating without them")
  }

  /// The other side of it: an ask launchd refused fixed nothing, so a later failure asks again
  /// and the delay keeps escalating in the meantime.
  func testARefusedRegistrationIsAskedAgainAndDoesNotRewind() async {
    var backoff = Self.backoff(registerEvery: 3)
    var registrations = 0

    let seen = await Self.delays(of: &backoff, over: 6) {
      registrations += 1
      return false
    }

    XCTAssertEqual(registrations, 2, "the third and sixth failures both ask")
    XCTAssertEqual(seen, [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(8), .seconds(8)])
  }

  /// Nothing has gone wrong yet, and zero is a multiple of every threshold, so the guard against
  /// registering before the first failure has to be explicit.
  func testTheAgentIsNotRegisteredBeforeAnyFailure() async {
    var backoff = Self.backoff(registerEvery: 3)
    var registrations = 0

    await backoff.registerAgentIfDue {
      registrations += 1
      return true
    }

    XCTAssertEqual(registrations, 0)
  }

  func testTheAgentIsNotRegisteredBeforeTheThresholdFailure() async {
    var backoff = Self.backoff(registerEvery: 3)
    var registrations = 0

    _ = await Self.delays(of: &backoff, over: 2) {
      registrations += 1
      return true
    }

    XCTAssertEqual(registrations, 0)
  }

  func testAFrameFromTheDaemonStartsTheNextOutageFromScratch() async {
    var backoff = Self.backoff(registerEvery: 3)
    _ = await Self.delays(of: &backoff, over: 4)
    backoff.reset()

    var registrations = 0
    let seen = await Self.delays(of: &backoff, over: 3) {
      registrations += 1
      return true
    }

    XCTAssertEqual(backoff.failures, 3)
    XCTAssertEqual(seen.first, .seconds(1))
    XCTAssertEqual(registrations, 1, "the new outage may ask launchd again")
  }

  // MARK: Private

  private static func backoff(registerEvery: Int) -> ReconnectBackoff {
    ReconnectBackoff(delays: [.seconds(1), .seconds(2), .seconds(4), .seconds(8)], registerEvery: registerEvery)
  }

  /// Runs `failures` failed dials, offering each one the chance to register, and reports the
  /// delay the backoff asked for after each.
  private static func delays(
    of backoff: inout ReconnectBackoff,
    over failures: Int,
    register: () async -> Bool = { true },
  ) async -> [Duration] {
    var seen = [Duration]()
    for _ in 1...failures {
      backoff.recordFailure()
      await backoff.registerAgentIfDue(register)
      seen.append(backoff.delay)
    }
    return seen
  }

}

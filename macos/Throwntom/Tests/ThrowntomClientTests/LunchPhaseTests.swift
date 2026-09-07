import XCTest
@testable import ThrowntomClient

/// Lunch is a phase the daemon can publish and a verb the client can send. It is chosen rather
/// than earned (`internal/engine/engine.go`), so nothing in the timer's own flow leads to it.
///
/// Decoding the wire name is covered by `StateDecodingTests.testDecodesEveryPhaseName`, which
/// builds its document from the one State fixture the whole target shares; a second literal here
/// would only rot the next time the daemon gains a field.
@MainActor
final class LunchPhaseTests: XCTestCase {

  // MARK: Internal

  func testLunchIsNamedInTheWindow() {
    XCTAssertEqual(DaemonState.Phase.lunch.displayName, "Lunch")
  }

  func testLunchPostsToItsOwnTimerVerb() {
    XCTAssertEqual(TimerAction.lunch.verb, .lunch)
    XCTAssertEqual(TimerVerb.lunch.rawValue, "lunch")
    XCTAssertEqual(TimerAction.lunch.title, "Lunch")
  }

  /// Lunch is chosen rather than earned, so it is offered wherever there is a daemon to take it —
  /// the same rule meeting follows — except while it is already running, where starting it again
  /// would only restart the hour and the way out is the Skip chip beside it.
  func testLunchIsOfferedAsAChipInEveryStateButLunch() {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused] {
      XCTAssertTrue(
        TimerActions.available(for: makeClientState(phase: phase)).contains(.lunch),
        "\(phase) does not offer lunch as a chip",
      )
    }
    XCTAssertFalse(TimerActions.available(for: makeClientState(phase: .lunch)).contains(.lunch))
    XCTAssertTrue(TimerAction.lunch.shortcutHint.isEmpty)
  }

  /// A running lunch offers what every other running phase offers, minus a lunch chip of its own.
  func testLunchOffersTheRunningPhaseVerbs() {
    XCTAssertEqual(TimerActions.available(for: makeClientState(phase: .lunch)), [.pause, .skip, .meeting, .skipToday])
  }

  func testTheMenuOffersThirtyAndSixtyMinutesThenACustomLength() {
    XCTAssertEqual(LunchActions.presets, [30, 60])
    XCTAssertEqual(LunchActions.all, [.start(minutes: 30), .start(minutes: 60), .custom])
  }

  func testTheLengthsAreTitledTheWaySnoozesAre() {
    XCTAssertEqual(LunchAction.start(minutes: 30).title, "30 minutes")
    XCTAssertEqual(LunchAction.start(minutes: 60).title, "1 hour")
    XCTAssertEqual(LunchAction.custom.title, "Custom…")
  }

  /// `Custom…` is a question for the user, so there is nothing to send until they answer it.
  func testACustomLengthAsksTheUserRatherThanTheDaemon() {
    XCTAssertNil(LunchAction.custom.request)
    XCTAssertEqual(LunchAction.start(minutes: 45).request, .start(minutes: 45))
  }

  func testChoosingAnExplicitLengthPostsItToTheLunchRoute() async throws {
    let (client, transport) = makeLunchClient()

    try await client.perform(LunchRequest.start(minutes: 45))

    let request = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.path, "/v1/timer/lunch")
    let body = try XCTUnwrap(request.body)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Int])
    XCTAssertEqual(decoded, ["minutes": 45])
  }

  /// A plain click keeps the daemon's own answer for how long lunch runs: no body at all, rather
  /// than a preset the user never chose.
  func testThePlainLunchVerbSendsNoBody() async throws {
    let (client, transport) = makeLunchClient()

    try await client.perform(TimerAction.lunch)

    let request = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(request.path, "/v1/timer/lunch")
    XCTAssertNil(request.body)
  }

  // MARK: Private

  private func makeLunchClient() -> (DaemonClient, RecordingTransport) {
    let transport = RecordingTransport()
    return (DaemonClient(transport: transport, registrar: RecordingRegistrar()), transport)
  }

}

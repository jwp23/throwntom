import XCTest
@testable import ThrowntomClient

/// A meeting is a phase the daemon can publish and a length the client can ask for. Like snooze
/// it carries a duration, so it posts a body rather than a bare verb; unlike lunch it is a chip
/// the user can reach without opening a menu.
///
/// Decoding the wire name is covered by `StateDecodingTests.testDecodesEveryPhaseName`, which
/// builds its document from the one State fixture the whole target shares.
@MainActor
final class MeetingPhaseTests: XCTestCase {

  // MARK: Internal

  func testMeetingIsNamedInTheWindow() {
    XCTAssertEqual(DaemonState.Phase.meeting.displayName, "Meeting")
  }

  func testTheMenuOffersThirtyAndSixtyMinutesThenACustomLengthAndTheUndo() {
    XCTAssertEqual(MeetingActions.presets, [30, 60])
    XCTAssertEqual(MeetingActions.all, [.start(minutes: 30), .start(minutes: 60), .custom, .end])
  }

  /// A plain click takes the shortest preset, which is what the chip's primary action sends.
  func testThePlainClickTakesTheShortestPreset() {
    XCTAssertEqual(MeetingActions.defaultMinutes, 30)
    XCTAssertEqual(MeetingActions.presets.min(), MeetingActions.defaultMinutes)
  }

  func testTheLengthsAreTitledTheWaySnoozesAre() {
    XCTAssertEqual(MeetingAction.start(minutes: 30).title, "30 minutes")
    XCTAssertEqual(MeetingAction.start(minutes: 60).title, "1 hour")
    XCTAssertEqual(MeetingAction.custom.title, "Custom…")
    XCTAssertEqual(MeetingAction.end.title, "End Meeting")
  }

  /// `Custom…` is a question for the user, so there is nothing to send until they answer it.
  func testACustomLengthAsksTheUserRatherThanTheDaemon() {
    XCTAssertNil(MeetingAction.custom.request)
    XCTAssertEqual(MeetingAction.start(minutes: 45).request, .start(minutes: 45))
    XCTAssertEqual(MeetingAction.end.request, .end)
  }

  func testStartingAMeetingPostsItsMinutesToItsOwnRoute() async throws {
    let (client, transport) = makeMeetingClient()

    try await client.perform(MeetingRequest.start(minutes: 45))

    let request = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.path, "/v1/timer/meeting")
    let body = try XCTUnwrap(request.body)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Int])
    XCTAssertEqual(decoded, ["minutes": 45])
  }

  /// Ending a meeting early is the daemon's `skip`: the phase ends where a skip ends it, and the
  /// daemon credits the time spent rather than discarding it (`internal/core/commands.go`).
  func testEndingAMeetingAsksForASkip() async throws {
    let (client, transport) = makeMeetingClient()

    try await client.perform(MeetingRequest.end)

    let request = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(request.path, "/v1/timer/skip")
    XCTAssertNil(request.body)
  }

  /// The action with no verb of its own takes the default length, the way a bare snooze does.
  func testTheBareMeetingActionTakesTheDefaultLength() async throws {
    let (client, transport) = makeMeetingClient()

    try await client.perform(TimerAction.meeting)

    let request = try XCTUnwrap(transport.requests.last)
    XCTAssertEqual(request.path, "/v1/timer/meeting")
    let body = try XCTUnwrap(request.body)
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Int])
    XCTAssertEqual(decoded, ["minutes": MeetingActions.defaultMinutes])
  }

  /// Snooze and meeting are the two actions that carry a length. Neither may be dispatched as a
  /// bare verb path, and neither may be mistaken for the other.
  func testTheTwoLengthCarryingActionsHaveNoBareVerb() {
    XCTAssertNil(TimerAction.snooze.verb)
    XCTAssertNil(TimerAction.meeting.verb)
  }

  /// A meeting can start from anywhere: the user does not choose when they are called into one.
  func testAMeetingIsOfferedInEveryState() {
    for phase in DaemonState.Phase.allCases {
      XCTAssertTrue(
        TimerActions.available(for: makeClientState(phase: phase)).contains(.meeting),
        "\(phase) does not offer a meeting",
      )
    }
  }

  /// Skip and End Meeting would be two chips for one outcome, so a running meeting drops Skip:
  /// the meeting chip is where ending it belongs, as cancelling a snooze belongs on the snooze
  /// chip.
  func testARunningMeetingOffersNoSeparateSkip() {
    let available = TimerActions.available(for: makeClientState(phase: .meeting))
    XCTAssertFalse(available.contains(.skip))
    XCTAssertTrue(available.contains(.pause))
    XCTAssertTrue(available.contains(.meeting))
  }

  /// Every other running phase keeps the Skip it had.
  func testTheOtherRunningPhasesStillOfferSkip() {
    for phase in [DaemonState.Phase.work, .shortBreak, .longBreak, .lunch] {
      XCTAssertTrue(
        TimerActions.available(for: makeClientState(phase: phase)).contains(.skip),
        "\(phase) lost its skip",
      )
    }
  }

  func testTheMeetingChipCarriesNoKeyHint() {
    XCTAssertTrue(TimerAction.meeting.shortcutHint.isEmpty)
  }

  // MARK: Private

  private func makeMeetingClient() -> (DaemonClient, RecordingTransport) {
    let transport = RecordingTransport()
    return (DaemonClient(transport: transport, registrar: RecordingRegistrar()), transport)
  }

}

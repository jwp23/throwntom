import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// A meeting shares work's ground, so everything else the window draws has to tell them apart:
/// the name, the pose, and the chip that offers the way out of one.
@MainActor
final class MeetingPresentationTests: XCTestCase {

  // MARK: Internal

  func testAMeetingWearsWorksOrangeRatherThanAGroundOfItsOwn() {
    let meeting = Palette.scheme(for: .meeting)

    XCTAssertEqual(meeting, Palette.scheme(for: .work))
    XCTAssertNotEqual(meeting, Palette.scheme(for: nil), "a meeting must not fall back to disconnected")
    XCTAssertGreaterThanOrEqual(Contrast.ratio(meeting.text, meeting.ground), 4.5)
    XCTAssertGreaterThanOrEqual(Contrast.ratio(meeting.secondaryChipText, meeting.secondaryChip), 4.5)
    XCTAssertGreaterThanOrEqual(Contrast.ratio(meeting.panelText, meeting.panel), 4.5)
  }

  func testTheWindowNamesAMeetingAndCountsItDown() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let content = content(makeState(phase: .meeting, phaseEndAt: now.addingTimeInterval(1800)), now: now)

    XCTAssertEqual(content.title, "Meeting")
    XCTAssertEqual(content.countdown, "30:00")
    XCTAssertEqual(content.scheme, Palette.scheme(for: .work))
    XCTAssertTrue(content.isMeeting)
  }

  func testTheChipStartsTheDefaultLengthOnAPlainClickAndOffersTheRest() throws {
    let chip = try chip(phase: .idle)

    XCTAssertFalse(chip.isMeeting)
    XCTAssertEqual(chip.title, "Meeting")
    XCTAssertEqual(chip.primaryAction, .start(minutes: MeetingActions.defaultMinutes))
    XCTAssertEqual(chip.menu.items.map(\.action), [
      .start(minutes: 30),
      .start(minutes: 60),
      .custom,
      .end,
    ])
  }

  /// While a meeting runs the same chip is the way out of it, the way the snooze chip becomes
  /// Cancel Snooze: the undo belongs on the control that caused the thing.
  func testTheChipBecomesTheWayOutWhileAMeetingRuns() throws {
    let chip = try chip(phase: .meeting)

    XCTAssertTrue(chip.isMeeting)
    XCTAssertEqual(chip.title, "End Meeting")
    XCTAssertEqual(chip.primaryAction, .end)
  }

  /// The lengths stay live during a meeting so one that overruns can be restarted at a longer
  /// length; the way out is live only when there is a meeting to leave.
  func testTheMenuEnablesTheWayOutOnlyDuringAMeeting() throws {
    let running = MenuModel.meeting(canStart: true, isMeeting: true)
    let notRunning = MenuModel.meeting(canStart: true, isMeeting: false)

    XCTAssertTrue(try XCTUnwrap(running.item(for: .end)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(notRunning.item(for: .end)).isEnabled)
    for action in [MeetingAction.start(minutes: 30), .start(minutes: 60), .custom] {
      XCTAssertTrue(try XCTUnwrap(running.item(for: action)).isEnabled, "\(action)")
      XCTAssertTrue(try XCTUnwrap(notRunning.item(for: action)).isEnabled, "\(action)")
    }
  }

  /// The chip is secondary in every state: a meeting is something that happens to the user, not
  /// the thing the window is asking them to press.
  func testTheChipIsNeverThePrimaryOne() {
    for phase in DaemonState.Phase.allCases {
      XCTAssertNotEqual(content(makeState(phase: phase), now: Date()).primaryChip, .meeting, "\(phase)")
    }
  }

  /// A client with no daemon draws no chips at all, so it cannot offer to end a meeting it has
  /// no way to end.
  func testAWindowWithoutADaemonOffersNoMeeting() {
    let content = MainWindowContent(
      state: nil,
      connection: .stopped,
      status: .stopped,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: Date(),
    )

    XCTAssertFalse(content.chips.contains(TimerAction.meeting))
    XCTAssertFalse(content.isMeeting)
  }

  /// The menu bar is the complete command list, so it carries the meeting the chip row offers.
  /// Unlike lunch it stays enabled during one, where the same item is the way out.
  func testTheTimerMenuOffersAMeetingInEveryStateIncludingAMeeting() throws {
    for phase in DaemonState.Phase.allCases {
      let menu = MenuModel.timer(state: makeState(phase: phase), returnIsTaken: false, daemonAvailable: true)
      XCTAssertTrue(try XCTUnwrap(menu.item(for: .meeting)).isEnabled, "\(phase)")
    }
  }

  func testAMeetingIsWithdrawnWithTheDaemon() throws {
    let gone = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: false)
    XCTAssertFalse(try XCTUnwrap(gone.item(for: .meeting)).isEnabled)
    let noState = MenuModel.timer(state: nil, returnIsTaken: false, daemonAvailable: true)
    XCTAssertFalse(try XCTUnwrap(noState.item(for: .meeting)).isEnabled)
  }

  func testAMeetingSitsWithTheCycleVerbsAndBindsNoKey() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(menu.groups.last?.map(\.action), [.skipToday, .newCycle, .lunch, .meeting])
    XCTAssertNil(try XCTUnwrap(menu.item(for: .meeting)).shortcut)
  }

  /// Escape closes the length field before anything else, the way it closes the snooze field.
  func testEscapeClosesTheLengthFieldFirst() {
    let model = WindowModel()
    model.isEnteringMeeting = true
    model.showsShortcuts = true

    XCTAssertTrue(model.dismiss(panelIsShown: false))
    XCTAssertFalse(model.isEnteringMeeting)
    XCTAssertTrue(model.showsShortcuts, "the sheet must outlast the field Escape was answering")
  }

  func testATypedLengthIsRefusedUnlessItIsAWholeNumberOfMinutes() {
    for entry in ["", " ", "abc", "1.5", "30m", "0", "-5", "\(Minutes.maximum + 1)"] {
      XCTAssertNil(Minutes.parse(entry), entry)
    }
    XCTAssertEqual(Minutes.parse("45"), 45)
    XCTAssertEqual(Minutes.parse("\(Minutes.maximum)"), Minutes.maximum)
  }

  // MARK: Private

  private func chip(phase: DaemonState.Phase) throws -> MeetingChip {
    let environment = try AppEnvironment(transport: StubTransport(states: []))
    return MeetingChip(
      content: content(makeState(phase: phase), now: Date()),
      client: environment.client,
      model: environment.windowModel,
    )
  }

  private func content(_ state: DaemonState, now: Date) -> MainWindowContent {
    MainWindowContent(
      state: state,
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: now,
    )
  }

}

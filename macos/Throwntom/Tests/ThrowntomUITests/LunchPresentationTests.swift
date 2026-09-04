import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// Lunch shares the long break's ground, so everything else the window draws has to tell them
/// apart: the name, the pose, and the garden underneath.
final class LunchPresentationTests: XCTestCase {

  // MARK: Internal

  func testLunchWearsTheRestBlueRatherThanAGroundOfItsOwn() {
    let lunch = Palette.scheme(for: .lunch)

    XCTAssertEqual(lunch, Palette.scheme(for: .longBreak))
    XCTAssertNotEqual(lunch, Palette.scheme(for: nil), "lunch must not fall back to disconnected")
    XCTAssertGreaterThanOrEqual(Contrast.ratio(lunch.text, lunch.ground), 4.5)
    XCTAssertGreaterThanOrEqual(Contrast.ratio(lunch.secondaryChipText, lunch.secondaryChip), 4.5)
    XCTAssertGreaterThanOrEqual(Contrast.ratio(lunch.panelText, lunch.panel), 4.5)
  }

  /// With the ground shared, the pose is what separates lunch from the long break on sight.
  func testLunchHasItsOwnPose() {
    let pose = MascotPose.pose(for: .lunch, pausedFrom: .idle)

    XCTAssertEqual(pose.held, .burger)
    XCTAssertNil(pose.furniture)
    XCTAssertNotEqual(pose, MascotPose.pose(for: .longBreak, pausedFrom: .idle))
    XCTAssertEqual(MascotPose.pose(for: .paused, pausedFrom: .lunch).held, .burger)
    XCTAssertEqual(MascotPose.pose(for: .paused, pausedFrom: .lunch).eyes, .closed)
  }

  func testTheWindowNamesLunchAndCountsItDown() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let content = content(makeState(phase: .lunch, phaseEndAt: now.addingTimeInterval(1800)), now: now)

    XCTAssertEqual(content.title, "Lunch")
    XCTAssertEqual(content.countdown, "30:00")
    XCTAssertEqual(content.pose, MascotPose.lunch)
    XCTAssertEqual(content.scheme, Palette.scheme(for: .longBreak))
  }

  /// The daemon zeroes work_sessions_in_block when lunch begins, and what that buys is drawn
  /// here: the same six pomodoros group differently either side of the reset. Un-taken, the
  /// second block is padded with dim slots promising a long break two pomodoros away; once lunch
  /// has closed the block, those slots are gone, because that long break is no longer coming.
  func testTheGardenClosesTheBlockLunchEnded() {
    let afterLunch = TomatoGarden(completedToday: 6, inBlock: 0, every: 4).blocks
    let hadLunchNotBeenTaken = TomatoGarden(completedToday: 6, inBlock: 2, every: 4).blocks

    XCTAssertEqual(afterLunch, [[true, true, true, true], [true, true]])
    XCTAssertEqual(hadLunchNotBeenTaken, [[true, true, true, true], [true, true, false, false]])
    XCTAssertNotEqual(afterLunch, hadLunchNotBeenTaken)
  }

  /// The first pomodoro back opens a block of its own, rather than resuming the one lunch closed.
  func testTheFirstPomodoroBackOpensAFreshBlock() {
    XCTAssertEqual(
      TomatoGarden(completedToday: 7, inBlock: 1, every: 4).blocks,
      [[true, true, true, true], [true, true], [true, false, false, false]],
    )
  }

  /// Lunch is chosen, not earned, so the menu offers it whatever the timer is doing — except
  /// while it is already running, where starting it again would only restart the hour.
  func testTheTimerMenuOffersLunchInEveryStateButLunch() throws {
    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .awaitingConfirm, .paused] {
      let menu = MenuModel.timer(state: makeState(phase: phase), returnIsTaken: false, daemonAvailable: true)
      XCTAssertTrue(try XCTUnwrap(menu.item(for: .lunch)).isEnabled, "\(phase)")
    }
    let atLunch = MenuModel.timer(state: makeState(phase: .lunch), returnIsTaken: false, daemonAvailable: true)
    XCTAssertFalse(try XCTUnwrap(atLunch.item(for: .lunch)).isEnabled)
  }

  func testLunchIsWithdrawnWithTheDaemon() throws {
    let gone = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: false)
    XCTAssertFalse(try XCTUnwrap(gone.item(for: .lunch)).isEnabled)
    let noState = MenuModel.timer(state: nil, returnIsTaken: false, daemonAvailable: true)
    XCTAssertFalse(try XCTUnwrap(noState.item(for: .lunch)).isEnabled)
  }

  /// Lunch sits with the other verbs that discard where the cycle was, below the separator, and
  /// binds no key: throwntom-bxd.17's shortcut audit owns what is bound.
  func testLunchSitsWithTheCycleVerbsAndBindsNoKey() throws {
    let menu = MenuModel.timer(state: makeState(phase: .idle), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(menu.groups.last?.map(\.action), [.skipToday, .newCycle, .lunch])
    XCTAssertNil(try XCTUnwrap(menu.item(for: .lunch)).shortcut)
  }

  // MARK: Private

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

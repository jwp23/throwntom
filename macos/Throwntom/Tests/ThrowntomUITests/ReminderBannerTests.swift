import Foundation
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// What each change in the daemon's state means for the reminder banner. The daemon sends a frame
/// per tick, so the rule is about what changed between two frames rather than about the latest one.
final class ReminderBannerTests: XCTestCase {

  // MARK: Internal

  func testTheDaemonWaitingForAnAnswerRaisesTheBanner() {
    let banner = decide(from: makeState(phase: .work), to: makeState(phase: .awaitingConfirm, nextStage: shortBreak))

    XCTAssertEqual(banner, .post(title: "Throwntom", body: "Short break 5 min"))
  }

  func testTheFirstStateTheAppEverSeesCanAlreadyBeWaiting() {
    let banner = decide(from: nil, to: makeState(phase: .awaitingConfirm, nextStage: shortBreak))

    XCTAssertEqual(banner, .post(title: "Throwntom", body: "Short break 5 min"))
  }

  /// The event stream sends a frame per tick. Posting on each one would re-alert the user for as
  /// long as the reminder goes unanswered.
  func testRepeatedFramesOfTheSameWaitLeaveTheBannerAlone() {
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)
    let laterTick = makeState(
      phase: .awaitingConfirm,
      nextStage: shortBreak,
      phaseEndAt: Date(timeIntervalSince1970: 1),
    )

    XCTAssertEqual(decide(from: waiting, to: waiting), .unchanged)
    XCTAssertEqual(decide(from: waiting, to: laterTick), .unchanged)
  }

  func testEveryPhaseButWaitingWithdrawsTheBanner() {
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    for phase in [DaemonState.Phase.idle, .work, .shortBreak, .longBreak, .paused] {
      XCTAssertEqual(decide(from: waiting, to: makeState(phase: phase)), .withdraw, "\(phase)")
    }
  }

  func testASnoozeTheDaemonAcceptedWithdrawsTheBanner() {
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)
    let snoozed = makeState(
      phase: .awaitingConfirm,
      nextStage: shortBreak,
      snoozeUntil: Date(timeIntervalSince1970: 1),
    )

    XCTAssertEqual(decide(from: waiting, to: snoozed), .withdraw)
  }

  func testASnoozeRunningOutRaisesTheBannerAgain() {
    let snoozed = makeState(
      phase: .awaitingConfirm,
      nextStage: shortBreak,
      snoozeUntil: Date(timeIntervalSince1970: 1),
    )
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    XCTAssertEqual(decide(from: snoozed, to: waiting), .post(title: "Throwntom", body: "Short break 5 min"))
  }

  func testAWaitWithNoNamedStageStillSaysSomething() {
    let banner = decide(from: makeState(phase: .work), to: makeState(phase: .awaitingConfirm))

    XCTAssertEqual(banner, .post(title: "Throwntom", body: "Ready for the next stage."))
  }

  func testNothingIsPostedWhileMacOSWillNotDeliverReminders() {
    let banner = decide(
      from: makeState(phase: .work),
      to: makeState(phase: .awaitingConfirm, nextStage: shortBreak),
      authorization: .reported(.denied),
    )

    XCTAssertEqual(banner, .unchanged)
  }

  func testTimerChangesWithNoReminderInThemLeaveTheBannerAlone() {
    XCTAssertEqual(decide(from: makeState(phase: .idle), to: makeState(phase: .work)), .unchanged)
    XCTAssertEqual(decide(from: nil, to: makeState(phase: .work)), .unchanged)
  }

  func testTheMorningNudgeRaisesItsOwnBanner() {
    let banner = decide(
      from: makeState(phase: .work),
      to: makeState(phase: .idle, morningPending: true),
    )

    XCTAssertEqual(banner, .postMorning(title: "Throwntom", body: "Ready to start your day?"))
  }

  func testRepeatedFramesOfTheMorningWaitLeaveTheBannerAlone() {
    let waiting = makeState(phase: .idle, morningPending: true)

    XCTAssertEqual(decide(from: waiting, to: waiting), .unchanged)
  }

  func testAMorningSnoozeTheDaemonAcceptedWithdrawsTheBanner() {
    let waiting = makeState(phase: .idle, morningPending: true)
    let snoozed = makeState(phase: .idle, morningPending: true, snoozeUntil: Date(timeIntervalSince1970: 1))

    XCTAssertEqual(decide(from: waiting, to: snoozed), .withdraw)
  }

  func testAMorningSnoozeRunningOutRaisesTheBannerAgain() {
    let snoozed = makeState(phase: .idle, morningPending: true, snoozeUntil: Date(timeIntervalSince1970: 1))
    let waiting = makeState(phase: .idle, morningPending: true)

    XCTAssertEqual(
      decide(from: snoozed, to: waiting),
      .postMorning(title: "Throwntom", body: "Ready to start your day?"),
    )
  }

  func testIdleWithNoMorningPendingLeavesTheBannerAlone() {
    XCTAssertEqual(decide(from: nil, to: makeState(phase: .idle)), .unchanged)
  }

  func testNothingIsPostedForTheMorningNudgeWhileMacOSWillNotDeliverReminders() {
    let banner = decide(
      from: makeState(phase: .work),
      to: makeState(phase: .idle, morningPending: true),
      authorization: .reported(.denied),
    )

    XCTAssertEqual(banner, .unchanged)
  }

  /// If authorization is withdrawn while a cycle banner is showing and the daemon jumps
  /// straight to the morning wait, the stale cycle banner must come down even though nothing
  /// new can be posted in its place.
  func testALostAuthorizationWithdrawsAStaleCycleBannerBeforeTheMorningWait() {
    let banner = decide(
      from: makeState(phase: .awaitingConfirm, nextStage: shortBreak),
      to: makeState(phase: .idle, morningPending: true),
      authorization: .reported(.denied),
    )

    XCTAssertEqual(banner, .withdraw)
  }

  /// The same stale-banner bug, the other direction: a morning banner is showing when
  /// authorization is lost and the daemon moves straight to the cycle wait.
  func testALostAuthorizationWithdrawsAStaleMorningBannerBeforeTheCycleWait() {
    let banner = decide(
      from: makeState(phase: .idle, morningPending: true),
      to: makeState(phase: .awaitingConfirm, nextStage: shortBreak),
      authorization: .reported(.denied),
    )

    XCTAssertEqual(banner, .withdraw)
  }

  /// The same stale-banner bug again, without any state transition at all: authorization is
  /// lost between two frames that report the identical wait, so the early "nothing changed"
  /// return must not skip the authorization check.
  func testALostAuthorizationWithdrawsAStaleBannerAcrossRepeatedFramesOfTheSameWait() {
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    let banner = decide(from: waiting, to: waiting, authorization: .reported(.denied))

    XCTAssertEqual(banner, .withdraw)
  }

  func testWantsAttentionOnAFreshWaitRegardlessOfAuthorization() {
    XCTAssertTrue(ReminderBanner.wantsAttention(from: makeState(phase: .idle), to: makeState(phase: .awaitingConfirm)))
  }

  func testWantsAttentionIsFalseWhileTheSameWaitContinues() {
    let waiting = makeState(phase: .awaitingConfirm)
    XCTAssertFalse(ReminderBanner.wantsAttention(from: waiting, to: waiting))
  }

  func testWantsAttentionIsFalseLeavingTheWait() {
    XCTAssertFalse(ReminderBanner.wantsAttention(from: makeState(phase: .awaitingConfirm), to: makeState(phase: .shortBreak)))
  }

  func testWantsAttentionOnTheFirstStateEverSeen() {
    XCTAssertTrue(ReminderBanner.wantsAttention(from: nil, to: makeState(phase: .awaitingConfirm)))
  }

  func testWantsAttentionOnAFreshMorningWait() {
    XCTAssertTrue(ReminderBanner.wantsAttention(from: makeState(phase: .idle), to: makeState(phase: .idle, morningPending: true)))
  }

  // MARK: Private

  private let shortBreak = DaemonState.NextStage(state: .shortBreak, duration: 300)
  private let deliverable = ReminderAuthorization()

  private func decide(
    from previous: DaemonState?,
    to current: DaemonState,
    authorization: ReminderAuthorization? = nil,
  ) -> ReminderBanner {
    ReminderBanner.decide(from: previous, to: current, authorization: authorization ?? deliverable)
  }

}

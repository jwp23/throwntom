import AppKit
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// How the app raises and removes the reminder banner as the daemon's state arrives. The banner is
/// the only way a reminder can be answered while the window is closed, and the app that posts it is
/// the only one macOS delivers the answer to.
@MainActor
final class ReminderPostingTests: XCTestCase {

  // MARK: Internal

  func testTheAppPostsTheReminderTheDaemonIsWaitingOn() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))

    XCTAssertEqual(presenter.posts, [.init(title: "Throwntom", body: "Short break 5 min")])
  }

  func testAReminderIsPostedOnceHoweverManyFramesTheWaitLasts() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    for _ in 0..<5 {
      await responder.present(waiting)
    }

    XCTAssertEqual(presenter.posts.count, 1)
  }

  func testAnsweringTheReminderTakesTheBannerDown() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))
    await responder.present(makeState(phase: .shortBreak))

    XCTAssertEqual(presenter.withdrawals, 1)
  }

  /// The app that posted the banner is the only one macOS delivers its answer to, so a banner left
  /// behind by a quit app offers buttons that can no longer do anything.
  func testQuittingTheAppTakesTheBannerDown() throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    responder.withdrawOnTermination()

    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

    XCTAssertEqual(presenter.withdrawals, 1)
  }

  func testAReminderMacOSRefusesIsReportedWhereTheUserCanSeeIt() async throws {
    let presenter = StubReminderPresenter()
    presenter.refusal = notificationsNotAllowed
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))

    XCTAssertEqual(
      responder.authorization.problem,
      "Reminders will not appear: macOS would not allow them.",
    )
  }

  /// The whole path: a frame off the daemon's event stream ends up as a banner, with no view on
  /// screen to notice it. The window is closed almost all the time a reminder arrives.
  func testAWaitArrivingOnTheEventStreamRaisesTheBanner() async throws {
    let presenter = StubReminderPresenter()
    let environment = AppEnvironment(
      transport: try StubTransport(states: [makeState(phase: .awaitingConfirm, nextStage: shortBreak)]),
      presenter: presenter,
    )
    defer { environment.client.stop() }
    environment.responder.followDaemonState()

    environment.start()

    try await waitUntil { !presenter.posts.isEmpty }
    XCTAssertEqual(presenter.posts, [.init(title: "Throwntom", body: "Short break 5 min")])
  }

  func testTheAppPostsTheMorningNudgeTheDaemonIsWaitingOn() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .idle, morningPending: true))

    XCTAssertEqual(presenter.morningPosts, [.init(title: "Throwntom", body: "Ready to start your day?")])
    XCTAssertTrue(presenter.posts.isEmpty)
  }

  func testAWaitingPhaseBouncesTheDockOnce() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    await responder.present(waiting)
    await responder.present(waiting)

    XCTAssertEqual(presenter.attentionRequests, 1)
  }

  func testTheMorningNudgeBouncesTheDockToo() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .idle, morningPending: true))

    XCTAssertEqual(presenter.attentionRequests, 1)
  }

  /// Losing the daemon says nothing about whether the user still owes an answer, so a reconnect
  /// into the wait already on screen is silent: the same banner, posted once, bounced once.
  func testReconnectingIntoAnAlreadyShownWaitIsSilent() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    await responder.present(waiting)
    await responder.present(nil)
    await responder.present(waiting)

    XCTAssertEqual(presenter.attentionRequests, 1)
    XCTAssertEqual(presenter.posts.count, 1)
    XCTAssertEqual(presenter.withdrawals, 0)
  }

  /// The gap in what the app knows preserves the last state it decided from rather than freezing
  /// the banner: a reconnect into a *different* wait is still news, and still raises its banner.
  func testReconnectingIntoADifferentWaitStillPostsIt() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))
    await responder.present(nil)
    await responder.present(makeState(phase: .idle, morningPending: true))

    XCTAssertEqual(presenter.morningPosts.count, 1)
    XCTAssertEqual(presenter.attentionRequests, 2)
  }

  /// The banner is how an unanswered reminder is answered. A daemon we cannot read has not
  /// answered it, so taking the banner down would lose the reminder rather than retire it.
  func testLosingTheDaemonLeavesTheBannerUp() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))
    await responder.present(nil)

    XCTAssertEqual(presenter.withdrawals, 0)
  }

  /// Joe's requirement, 2026-08-29: the repeated chime is the reminder that works. The daemon
  /// plays no sound and the banner carries none (ADR-009), so every ring is sounded here —
  /// including the first, which arrives in the same breath as the banner.
  func testEachNewRingChimes() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = { (rings: Int) in
      makeState(phase: .awaitingConfirm, nextStage: self.shortBreak, reminderRings: rings)
    }

    await responder.present(waiting(1))
    XCTAssertEqual(presenter.posts.count, 1)
    XCTAssertEqual(presenter.chimes, 1, "ring one is sounded like any other ring")

    await responder.present(waiting(2))
    await responder.present(waiting(3))
    XCTAssertEqual(presenter.chimes, 3, "each further ring is sounded")
    XCTAssertEqual(presenter.posts.count, 1, "a ring is a chime, not another banner")
  }

  /// The live case the launch-time path used to hide: by the time a second wait comes round the
  /// app has long since read state, so ring one must be sounded by the chime or not at all.
  func testTheFirstRingOfALaterWaitChimes() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .work, reminderRings: 0))
    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 1))

    XCTAssertEqual(presenter.chimes, 1)
    XCTAssertEqual(presenter.posts.count, 1, "one banner, one chime — the reminder sounds once")
  }

  /// A wait already ringing when the app starts is still a reminder the user owes an answer to.
  /// Nothing else would sound it: the banner is silent and the ring it arrived on is in the past.
  func testAWaitAlreadyRingingWhenTheAppStartsIsHeard() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 1))

    XCTAssertEqual(presenter.chimes, 1)
  }

  /// A restarted daemon counts its rings from zero again, so the new wait's count can start below
  /// the one the app last heard. Waiting for it to climb past the old figure would leave a visibly
  /// waiting reminder silent for several rings.
  func testAWaitWhoseRingCountRestartedLowerStillChimes() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 3))
    let afterTheFirstWait = presenter.chimes
    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 1))

    XCTAssertEqual(presenter.chimes, afterTheFirstWait + 1)
  }

  /// Rings the app was not there to hear are adopted, not replayed: a gap of four rings is one
  /// reminder gone unanswered, not four alerts owed all at once.
  func testAGapOfManyRingsIsOneChimeNotOnePerRing() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 1))
    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 5))

    XCTAssertEqual(presenter.chimes, 2)
  }

  /// A repeat of the state the app has already seen is not a new ring, so it stays quiet.
  func testTheSameRingDoesNotChimeTwice() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 4)

    await responder.present(waiting)
    await responder.present(waiting)
    XCTAssertEqual(presenter.chimes, 1)
  }

  /// Retiring the wait resets the count, and a reset is not a ring: going back to zero must
  /// not be heard as a chime when the next wait begins.
  func testAResetRingCountDoesNotChime() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak, reminderRings: 3))
    let afterTheWait = presenter.chimes
    await responder.present(makeState(phase: .work, reminderRings: 0))
    XCTAssertEqual(presenter.chimes, afterTheWait)
  }

  /// A pause is easy to walk away from. The daemon says when one has been going too long; the
  /// bounce is what the app does about it.
  func testAForgottenPauseBouncesTheDock() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .paused, pausedFrom: .work))
    await responder.present(makeState(phase: .paused, pausedFrom: .work, pausedTooLong: true))

    XCTAssertEqual(presenter.attentionRequests, 1)
    XCTAssertTrue(presenter.posts.isEmpty)
  }

  /// `.criticalRequest` bounces until the app is activated, and resuming from the menu bar or the
  /// terminal never activates it. Nothing else would ever stop the Dock.
  func testResumingAForgottenPauseStopsTheBounce() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .paused, pausedFrom: .work, pausedTooLong: true))
    await responder.present(makeState(phase: .work))

    XCTAssertEqual(presenter.attentionRequests, 1)
    XCTAssertEqual(presenter.attentionCancels, 1)
  }

  func testAWaitingPhaseBouncesTheDockEvenWhenNotificationsAreDenied() async throws {
    let presenter = StubReminderPresenter()
    presenter.refusal = notificationsNotAllowed
    let responder = try makeResponder(presenter)

    await responder.present(makeState(phase: .awaitingConfirm, nextStage: shortBreak))

    XCTAssertEqual(presenter.attentionRequests, 1)
    XCTAssertTrue(presenter.posts.isEmpty)
  }

  // MARK: Private

  private let shortBreak = DaemonState.Stage(state: .shortBreak, duration: 300)

  private func makeResponder(_ presenter: StubReminderPresenter) throws -> ReminderResponder {
    AppEnvironment(transport: try StubTransport(states: []), presenter: presenter).responder
  }

}

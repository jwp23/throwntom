import AppKit
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// How the app raises and removes the reminder banner as the daemon's state arrives. The banner is
/// the only way a reminder can be answered while the popover is closed, and the app that posts it is
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
      "Reminders will not appear: Notifications are not allowed for this application",
    )
  }

  /// The whole path: a frame off the daemon's event stream ends up as a banner, with no view on
  /// screen to notice it. The popover is closed almost all the time a reminder arrives.
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

  func testReconnectingIntoAnAlreadyShownWaitDoesNotBounceAgain() async throws {
    let presenter = StubReminderPresenter()
    let responder = try makeResponder(presenter)
    let waiting = makeState(phase: .awaitingConfirm, nextStage: shortBreak)

    await responder.present(waiting)
    await responder.present(nil)
    await responder.present(waiting)

    XCTAssertEqual(presenter.attentionRequests, presenter.posts.count, "attention follows the banner exactly")
  }

  // MARK: Private

  private let shortBreak = DaemonState.NextStage(state: .shortBreak, duration: 300)

  private func makeResponder(_ presenter: StubReminderPresenter) throws -> ReminderResponder {
    AppEnvironment(transport: try StubTransport(states: []), presenter: presenter).responder
  }

}

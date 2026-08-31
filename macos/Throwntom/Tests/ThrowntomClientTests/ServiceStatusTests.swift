import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - ServiceStatusTests

/// The three ways the timer service can be absent. They must never be confusable: one is a
/// choice the user made, one is a launch that definitively failed, and one is not a failure at
/// all yet. A window that renders any two of them alike leaves the reader guessing which they
/// are in, and the guess decides whether they should be waiting or pressing something.
final class ServiceStatusTests: XCTestCase {

  // MARK: Internal

  func testAConnectedDaemonIsRunning() {
    XCTAssertEqual(status(.connected), .running)
  }

  func testEveryDiallingStateIsTheTransientOne() {
    for connection in [DaemonClient.Connection.connecting, .reconnecting(attempt: 2), .startingDaemon] {
      XCTAssertEqual(status(connection), .reaching, "\(connection)")
    }
  }

  func testAServiceTheUserStoppedIsItsOwnStatus() {
    XCTAssertEqual(status(.stopped), .stopped)
  }

  func testARefusedLaunchIsItsOwnStatus() {
    XCTAssertEqual(status(.startingDaemon, registrationFailed: true), .launchRefused)
  }

  func testAnAcceptedLaunchThatNeverArrivesIsItsOwnStatus() {
    XCTAssertEqual(status(.startingDaemon, startStalled: true), .notAnswering)
  }

  func testTheThreeAbsentStatusesAndTheTransientOneAreAllDistinct() {
    XCTAssertEqual(Set([ServiceStatus.stopped, .launchRefused, .notAnswering, .reaching]).count, 4)
  }

  /// A stop is the user's own decision, so it outranks whatever the dialling machinery was
  /// reporting when they made it.
  func testAStoppedServiceOutranksARefusalAndAStall() {
    XCTAssertEqual(status(.stopped, registrationFailed: true, startStalled: true), .stopped)
  }

  /// Matches `DaemonClient.unresolvedError`, which lets a live connection outrank a refusal so a
  /// stale one can never be shown over a running timer.
  func testALiveConnectionOutranksAStaleRefusalOrStall() {
    XCTAssertEqual(status(.connected, registrationFailed: true, startStalled: true), .running)
  }

  func testARefusalOutranksAStallBecauseItIsTheMoreSpecificAnswer() {
    XCTAssertEqual(status(.startingDaemon, registrationFailed: true, startStalled: true), .launchRefused)
  }

  // MARK: Private

  private func status(
    _ connection: DaemonClient.Connection,
    registrationFailed: Bool = false,
    startStalled: Bool = false,
  ) -> ServiceStatus {
    ServiceStatus.of(connection: connection, registrationFailed: registrationFailed, startStalled: startStalled)
  }

}

// MARK: - DaemonAffordanceTests

/// The one rule every affordance that reaches the daemon is gated on, so the window chips, the
/// Timer menu, the command chips, the Tasks menu and the panels cannot answer it differently.
final class DaemonAffordanceTests: XCTestCase {

  func testACommandIsOfferedWhileTheDaemonIsThereOrStillBeingDialled() {
    XCTAssertTrue(ServiceStatus.running.offersDaemonCommands)
    XCTAssertTrue(
      ServiceStatus.reaching.offersDaemonCommands,
      "dialling is not a failure and the retained phase is still counting",
    )
  }

  func testNoCommandIsOfferedOnAnyOfTheThreeAbsentStatuses() {
    for status in [ServiceStatus.stopped, .launchRefused, .notAnswering] {
      XCTAssertFalse(status.offersDaemonCommands, "\(status)")
    }
  }

}

// MARK: - ServiceExplanationTests

/// The sentence under the status line on the screens where the line alone leaves the reader
/// asking "why is nothing happening".
final class ServiceExplanationTests: XCTestCase {

  func testTheStoppedExplanationSaysTheUserStoppedItAndNamesTheWayBack() throws {
    let explanation = try XCTUnwrap(ServiceStatus.stopped.explanation)

    XCTAssertTrue(explanation.contains("You stopped"), explanation)
    XCTAssertTrue(explanation.contains(ServiceAction.start.title), explanation)
  }

  /// Joe's ruling on a stop that survives a relaunch: persistence is safe only because the window
  /// explains it, and an explanation that reads as a fault would trade one confusion for another.
  func testTheStoppedExplanationReadsAsAChoiceRatherThanAFault() throws {
    let explanation = try XCTUnwrap(ServiceStatus.stopped.explanation).lowercased()

    for fault in ["error", "failed", "refused", "could not", "can’t", "problem"] {
      XCTAssertFalse(explanation.contains(fault), "\(fault) in: \(explanation)")
    }
  }

  func testTheNotAnsweringExplanationSaysTheLaunchWasAcceptedAndNothingCame() throws {
    let explanation = try XCTUnwrap(ServiceStatus.notAnswering.explanation)

    XCTAssertTrue(explanation.contains("accepted"), explanation)
    XCTAssertTrue(explanation.contains("Login Items"), explanation)
  }

  /// A refused launch already has its sentence: the client writes `registrationError` at the
  /// moment launchd says no, and the window shows that. A second one here would double it up.
  func testTheStatusesThatNeedNoSentenceOfTheirOwnHaveNone() {
    XCTAssertNil(ServiceStatus.launchRefused.explanation)
    XCTAssertNil(ServiceStatus.running.explanation)
    XCTAssertNil(ServiceStatus.reaching.explanation)
  }

}

// MARK: - ServiceAnnouncementTests

/// What a change of service situation says to assistive technology, and — as much of the point —
/// when it says nothing at all.
final class ServiceAnnouncementTests: XCTestCase {

  /// throwntom-07o. When the service goes down the whole window transforms at once — the chips
  /// go, the panel closes, the title and the sentence change. A sighted user sees that; without
  /// this a VoiceOver user is told nothing and the likeliest reading is that the app has hung.
  /// The announcement is the title and the sentence, because those are what the screen now says.
  func testEachSettledAbsenceIsAnnouncedAsItsTitleAndItsSentence() throws {
    XCTAssertEqual(
      ServiceStatus.announcement(from: .running, to: .stopped),
      "Timer service stopped. " + (try XCTUnwrap(ServiceStatus.stopped.explanation)),
    )
    XCTAssertEqual(
      ServiceStatus.announcement(from: .running, to: .notAnswering),
      "Timer service isn\u{2019}t answering. " + (try XCTUnwrap(ServiceStatus.notAnswering.explanation)),
    )
    XCTAssertEqual(
      ServiceStatus.announcement(from: .running, to: .launchRefused),
      "Timer service can\u{2019}t launch.",
      "a refusal has no sentence of its own; the client writes registrationError instead",
    )
  }

  /// Coming back is worth saying: the window has just regained its phase, its countdown and every
  /// verb, and a reader who was told it went down is owed the other half.
  func testRecoveryFromASettledAbsenceIsAnnounced() {
    for absence in [ServiceStatus.stopped, .launchRefused, .notAnswering] {
      XCTAssertEqual(ServiceStatus.announcement(from: absence, to: .running), "Timer service running.", "\(absence)")
    }
  }

  /// This function is the *settled* wording only: what the window says once it has arrived
  /// somewhere. Dialling is not a settled situation, so it has no line here — its line is
  /// `dialLine(from:)`, and which of the two a moment calls for is `ServiceAnnouncer`'s decision.
  func testTheSettledWordingHasNoLineForDialling() {
    XCTAssertNil(ServiceStatus.announcement(from: .running, to: .reaching))
    XCTAssertNil(ServiceStatus.announcement(from: .reaching, to: .running))
    for absence in [ServiceStatus.stopped, .launchRefused, .notAnswering] {
      XCTAssertNil(ServiceStatus.announcement(from: absence, to: .reaching), "\(absence)")
    }
  }

  /// throwntom-92i. A window that still holds a phase marks its title `(reconnecting)` the moment
  /// the socket goes, and Joe's ruling on throwntom-7rb is that the mark stays visible with no
  /// debounce, delay or suppression. The spoken line is that mark: same moment, same fact.
  ///
  /// The wording turns on what the dial left, because the two waits are different things. Leaving
  /// a running service is a reconnection; leaving a service that was off — the user has just
  /// pressed Start — is a first attempt, and calling that "reconnecting" would be false.
  func testEnteringADialIsWordedForWhatTheDialLeft() {
    XCTAssertEqual(ServiceStatus.dialLine(from: .running), "Reconnecting.")
    for absence in [ServiceStatus.stopped, .launchRefused, .notAnswering] {
      XCTAssertEqual(ServiceStatus.dialLine(from: absence), "Starting the timer service.", "\(absence)")
    }
  }

  /// A VoiceOver user and a sighted user must be told the same thing, which means the spoken line
  /// has to *be* the window's title rather than a second copy of the same words. They are written
  /// as two separate literals, so only an assertion keeps them from drifting: change one wording
  /// and this fails rather than the two quietly disagreeing.
  func testTheSpokenLineIsTheWindowsOwnTitle() throws {
    for (status, connection) in [
      (ServiceStatus.stopped, DaemonClient.Connection.stopped),
      (.launchRefused, .startingDaemon),
      (.notAnswering, .startingDaemon),
    ] {
      let spoken = try XCTUnwrap(ServiceStatus.announcement(from: .running, to: status), "\(status)")
      let title = ConnectionStatus.text(connection: connection, status: status)

      XCTAssertTrue(spoken.hasPrefix(title + "."), "spoke \"\(spoken)\", window reads \"\(title)\"")
    }
  }

  /// A status that has not changed is not news. `onChange` should not fire on an equal value, but
  /// the rule belongs in the function rather than in the caller that happens to obey it.
  func testAnUnchangedStatusIsNotAnnounced() {
    for status in [ServiceStatus.running, .reaching, .stopped, .launchRefused, .notAnswering] {
      XCTAssertNil(ServiceStatus.announcement(from: status, to: status), "\(status)")
    }
  }

  /// The three absences must be told apart by ear as well as by eye — the same requirement the
  /// titles carry, applied to the channel a VoiceOver user actually has.
  func testTheThreeAbsencesAreAnnouncedDistinctly() {
    let spoken = [ServiceStatus.stopped, .launchRefused, .notAnswering]
      .compactMap { ServiceStatus.announcement(from: .running, to: $0) }

    XCTAssertEqual(spoken.count, 3)
    XCTAssertEqual(Set(spoken).count, 3, "\(spoken)")
  }

}

// MARK: - ServiceAnnouncerTests

/// The sequence, as opposed to the wording. Every recovery passes through `.reaching` on its way
/// back, so a rule that reads only the immediately previous situation cannot tell a Start that
/// worked from a socket that blinked. This is what tells them apart.
final class ServiceAnnouncerTests: XCTestCase {

  // MARK: Internal

  /// The user pressed Start Timer Service and it worked. They are owed that: the press is theirs,
  /// and silence after it reads as a control that did nothing. The dial in between is spoken too,
  /// but as the wait it is rather than as the arrival.
  func testAStartThatWorksIsAnnouncedEvenThoughItPassesThroughDialling() {
    var announcer = announcer(startingIn: .running)

    XCTAssertNotNil(announcer.announcement(for: .stopped))
    XCTAssertEqual(announcer.announcement(for: .reaching)?.text, "Starting the timer service.")
    XCTAssertEqual(announcer.announcement(for: .running), Announcement(
      text: "Timer service running.",
      priority: .interrupting,
    ))
  }

  /// The same shape from the other two absences: what matters is the situation left behind, not
  /// the dialling step in between.
  func testRecoveryIsAnnouncedFromEveryAbsence() {
    for absence in [ServiceStatus.launchRefused, .notAnswering] {
      var announcer = announcer(startingIn: absence)
      XCTAssertEqual(announcer.announcement(for: .reaching)?.text, "Starting the timer service.", "\(absence)")
      XCTAssertEqual(announcer.announcement(for: .running)?.text, "Timer service running.", "\(absence)")
    }
  }

  /// throwntom-92i. A blink of the socket leaves `running` and comes back to it within a backoff
  /// step. This used to be silent in both directions, which is exactly the gap: the window marks
  /// its title `(reconnecting)` for the whole of that blink, so a sighted reader is told and a
  /// VoiceOver reader was not. Both edges of the mark now speak.
  ///
  /// What keeps that from becoming an interruption mid-pomodoro is the priority, not silence: a
  /// queued line waits for VoiceOver to finish what it is saying and is dropped if it cannot be
  /// fitted in, where the three service-down lines interrupt.
  func testASocketBlipIsSpokenAtBothEdgesWithoutInterrupting() {
    var announcer = announcer(startingIn: .running)

    XCTAssertEqual(announcer.announcement(for: .reaching), Announcement(
      text: "Reconnecting.",
      priority: .queued,
    ))
    XCTAssertEqual(announcer.announcement(for: .running), Announcement(
      text: "Reconnected.",
      priority: .queued,
    ))
  }

  /// Repeated dial failures walk `.reaching` several times before settling. The wait was announced
  /// when it began and has not changed since, so the backoff steps say nothing — and none of them
  /// may erase the situation the announcer is measuring against.
  func testAProlongedDialSpeaksOnceAndDoesNotForgetWhatItLeft() {
    var announcer = announcer(startingIn: .stopped)

    XCTAssertEqual(announcer.announcement(for: .reaching)?.text, "Starting the timer service.")
    for step in 0..<3 {
      XCTAssertNil(announcer.announcement(for: .reaching), "backoff step \(step)")
    }
    XCTAssertEqual(announcer.announcement(for: .running)?.text, "Timer service running.")
  }

  /// Launching straight into a dial and arriving is not a recovery from anything: the user has
  /// just opened the window and is reading it, and nobody was told a service was missing.
  func testComingUpFromAColdStartIsNotAnnouncedAsARecovery() {
    var announcer = announcer(startingIn: .reaching)

    XCTAssertNil(announcer.announcement(for: .running))
  }

  /// A cold start that ends in one of the three still speaks: the window has just transformed into
  /// a screen the reader has no other way to be told about.
  func testAColdStartThatEndsInAnAbsenceIsStillAnnounced() {
    var announcer = announcer(startingIn: .reaching)

    XCTAssertEqual(announcer.announcement(for: .launchRefused), Announcement(
      text: "Timer service can\u{2019}t launch.",
      priority: .interrupting,
    ))
  }

  /// The same situation arriving twice is not news the second time.
  func testAStatusThatDoesNotChangeIsNotRepeated() {
    var announcer = announcer(startingIn: .running)

    XCTAssertNotNil(announcer.announcement(for: .stopped))
    XCTAssertNil(announcer.announcement(for: .stopped))
  }

  /// The three lines a reader must not miss are the ones that interrupt; the two transient ones
  /// wait their turn. Asserted as a set so a line added later has to be placed deliberately.
  func testOnlyTheSettledLinesInterrupt() {
    var announcer = announcer(startingIn: .running)

    XCTAssertEqual(announcer.announcement(for: .reaching)?.priority, .queued)
    XCTAssertEqual(announcer.announcement(for: .notAnswering)?.priority, .interrupting)
    XCTAssertEqual(announcer.announcement(for: .reaching)?.priority, .queued)
    XCTAssertEqual(announcer.announcement(for: .running)?.priority, .interrupting)
  }

  // MARK: Private

  /// An announcer that has already seen the situation the window came up in. That first sighting
  /// is deliberately silent — the app does not announce its own launch — which is asserted here
  /// rather than left implicit, since every test below depends on it.
  private func announcer(startingIn status: ServiceStatus) -> ServiceAnnouncer {
    var announcer = ServiceAnnouncer()
    XCTAssertNil(announcer.announcement(for: status), "the window coming up is not a change")
    return announcer
  }

}

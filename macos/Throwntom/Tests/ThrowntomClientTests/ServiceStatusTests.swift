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

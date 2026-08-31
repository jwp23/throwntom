import Foundation
import XCTest
@testable import ThrowntomClient

final class ConnectionStatusTests: XCTestCase {
  func testNilStateConnecting() {
    XCTAssertEqual(ConnectionStatus.text(connection: .connecting, status: .reaching), "Connecting…")
  }

  func testNilStateStartingDaemon() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .startingDaemon, status: .reaching),
      "Starting timer…",
    )
  }

  func testNilStateReconnecting() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .reconnecting(attempt: 2), status: .reaching),
      "Reconnecting…",
    )
  }

  func testNilStateConnected() {
    XCTAssertEqual(ConnectionStatus.text(connection: .connected, status: .running), "Throwntom")
  }

  func testNilStateStopped() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .stopped, status: .stopped),
      "Timer service stopped",
    )
  }

  /// A launchd refusal is definitive: nothing is starting, so the line must stop claiming a start
  /// is in progress and name what actually failed. The way out is the window's own Start Timer
  /// Service control, which the note beside this line points at.
  func testARefusedLaunchIsNamedRatherThanReportedAsStarting() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .startingDaemon, status: .launchRefused),
      "Timer service can\u{2019}t launch",
    )
  }

  /// The precedence itself now lives in `ServiceStatus.of`, so that is where it has to be checked:
  /// asserting the same line for three connection values through `text` would restate one equality
  /// three times, because on the refused path `text` never reads the connection at all.
  func testARefusedLaunchOutranksEveryDiallingState() {
    let dialling: [DaemonClient.Connection] = [.connecting, .reconnecting(attempt: 2), .startingDaemon]
    for connection in dialling {
      XCTAssertEqual(
        ServiceStatus.of(connection: connection, registrationFailed: true, startStalled: false),
        .launchRefused,
        "\(connection)",
      )
    }
    XCTAssertEqual(
      ConnectionStatus.text(connection: .startingDaemon, status: .launchRefused),
      "Timer service can\u{2019}t launch",
    )
  }

  /// A stopped service is not a failure, and the user asked for it: the refusal must not survive
  /// into the state that follows pressing Stop.
  func testAStoppedServiceIsStillReportedAsStopped() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .stopped, status: .stopped),
      "Timer service stopped",
    )
  }

  /// throwntom-azp. An accepted launch that brought no daemon reads as "starting" for ever if the
  /// connection state is all this line has to go on.
  func testAnAcceptedLaunchThatNeverArrivesIsNamedRatherThanReportedAsStarting() {
    XCTAssertEqual(
      ConnectionStatus.text(connection: .startingDaemon, status: .notAnswering),
      "Timer service isn\u{2019}t answering",
    )
  }

  /// A first dial is not "re"-anything, so the two waits get two lines. This pins the wording map
  /// only — it holds for any `Connection` handed to it, and so cannot say whether the client hands
  /// over the right one. That is the half of throwntom-ibf where the bug actually lived, and it is
  /// covered where it can fail: `ReconnectTests.testAFailedFirstDialIsStillWordedAsAFirstDial`.
  func testAFirstDialIsWordedAsAFirstDialAndALostOneAsALostOne() {
    XCTAssertEqual(ConnectionStatus.text(connection: .connecting, status: .reaching), "Connecting…")
    XCTAssertEqual(ConnectionStatus.text(connection: .reconnecting(attempt: 1), status: .reaching), "Reconnecting…")
    XCTAssertFalse(ConnectionStatus.text(connection: .connecting, status: .reaching).lowercased().contains("recon"))
  }

  /// The four lines a reader tells the situations apart by.
  func testEverySituationWithoutARunningTimerSaysSomethingDifferent() {
    let lines = [
      ConnectionStatus.text(connection: .stopped, status: .stopped),
      ConnectionStatus.text(connection: .startingDaemon, status: .launchRefused),
      ConnectionStatus.text(connection: .startingDaemon, status: .notAnswering),
      ConnectionStatus.text(connection: .startingDaemon, status: .reaching),
    ]

    XCTAssertEqual(Set(lines).count, lines.count, "\(lines)")
  }
}

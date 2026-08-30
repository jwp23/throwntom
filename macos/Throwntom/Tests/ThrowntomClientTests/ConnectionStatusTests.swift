import Foundation
import XCTest
@testable import ThrowntomClient

final class ConnectionStatusTests: XCTestCase {
  func testNilStateConnecting() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connecting, status: .reaching, now: .now), "Connecting…")
  }

  func testNilStateStartingDaemon() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .reaching, now: .now),
      "Starting timer…",
    )
  }

  func testNilStateReconnecting() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .reconnecting(attempt: 2), status: .reaching, now: .now),
      "Reconnecting…",
    )
  }

  func testNilStateConnected() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connected, status: .running, now: .now), "Throwntom")
  }

  func testNilStateStopped() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .stopped, status: .stopped, now: .now),
      "Timer service stopped",
    )
  }

  /// A launchd refusal is definitive: nothing is starting, so the line must stop claiming a start
  /// is in progress and name what actually failed. The way out is the window's own Start Timer
  /// Service control, which the note beside this line points at.
  func testARefusedLaunchIsNamedRatherThanReportedAsStarting() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .launchRefused, now: .now),
      "Timer service can\u{2019}t launch",
    )
  }

  func testARefusedLaunchOutranksEveryDiallingState() {
    let dialling: [DaemonClient.Connection] = [.connecting, .reconnecting(attempt: 2), .startingDaemon]
    for connection in dialling {
      XCTAssertEqual(
        ConnectionStatus.text(state: nil, connection: connection, status: .launchRefused, now: .now),
        "Timer service can\u{2019}t launch",
        "\(connection)",
      )
    }
  }

  /// A stopped service is not a failure, and the user asked for it: the refusal must not survive
  /// into the state that follows pressing Stop.
  func testAStoppedServiceIsStillReportedAsStopped() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .stopped, status: .stopped, now: .now),
      "Timer service stopped",
    )
  }

  /// throwntom-azp. An accepted launch that brought no daemon reads as "starting" for ever if the
  /// connection state is all this line has to go on.
  func testAnAcceptedLaunchThatNeverArrivesIsNamedRatherThanReportedAsStarting() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .notAnswering, now: .now),
      "Timer service isn\u{2019}t answering",
    )
  }

  /// The four lines a reader tells the situations apart by.
  func testEverySituationWithoutARunningTimerSaysSomethingDifferent() {
    let lines = [
      ConnectionStatus.text(state: nil, connection: .stopped, status: .stopped, now: .now),
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .launchRefused, now: .now),
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .notAnswering, now: .now),
      ConnectionStatus.text(state: nil, connection: .startingDaemon, status: .reaching, now: .now),
    ]

    XCTAssertEqual(Set(lines).count, lines.count, "\(lines)")
  }
}

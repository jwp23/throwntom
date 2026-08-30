import Foundation
import XCTest
@testable import ThrowntomClient

final class ConnectionStatusTests: XCTestCase {
  func testNilStateConnecting() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connecting, now: .now), "Connecting…")
  }

  func testNilStateStartingDaemon() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .startingDaemon, now: .now), "Starting timer…")
  }

  func testNilStateReconnecting() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .reconnecting(attempt: 2), now: .now),
      "Reconnecting…",
    )
  }

  func testNilStateConnected() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connected, now: .now), "Throwntom")
  }

  func testNilStateStopped() {
    XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .stopped, now: .now), "Timer service stopped")
  }

  /// A launchd refusal is definitive: nothing is starting, so the line must stop claiming a start
  /// is in progress and name what actually failed. The way out is the window's own Start Timer
  /// Service control, which the note beside this line points at.
  func testARefusedLaunchIsNamedRatherThanReportedAsStarting() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .startingDaemon, registrationFailed: true, now: .now),
      "Timer service can\u{2019}t launch",
    )
  }

  func testARefusedLaunchOutranksEveryDiallingState() {
    let dialling: [DaemonClient.Connection] = [.connecting, .reconnecting(attempt: 2), .startingDaemon]
    for connection in dialling {
      XCTAssertEqual(
        ConnectionStatus.text(state: nil, connection: connection, registrationFailed: true, now: .now),
        "Timer service can\u{2019}t launch",
        "\(connection)",
      )
    }
  }

  /// A stopped service is not a failure, and the user asked for it: the refusal must not survive
  /// into the state that follows pressing Stop.
  func testAStoppedServiceIsStillReportedAsStopped() {
    XCTAssertEqual(
      ConnectionStatus.text(state: nil, connection: .stopped, registrationFailed: false, now: .now),
      "Timer service stopped",
    )
  }
}

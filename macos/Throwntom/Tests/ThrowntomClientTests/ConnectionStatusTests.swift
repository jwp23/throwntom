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

  func testPlaceholderTextStopped() {
    XCTAssertEqual(
      ConnectionStatus.placeholderText(state: nil, connection: .stopped, now: .now),
      "Timer service stopped",
    )
  }

  func testPlaceholderTextNilWhenStatePresent() {
    let state = DaemonState(
      state: .idle,
      phaseEndAt: nil,
      pausedRemaining: 0,
      pausedFrom: .idle,
      completedToday: 0,
      workSessionsInBlock: 0,
      longBreakEvery: 4,
      nextStage: nil,
      morningPending: false,
      snoozeUntil: nil,
      statusLine: "Idle",
      focusedTaskIds: [],
      reminderRings: 0,
    )
    XCTAssertNil(ConnectionStatus.placeholderText(state: state, connection: .connected, now: .now))
  }

  func testPlaceholderTextConnecting() {
    XCTAssertEqual(
      ConnectionStatus.placeholderText(state: nil, connection: .connecting, now: .now),
      "Connecting…",
    )
  }

  func testPlaceholderTextStartingDaemon() {
    XCTAssertEqual(
      ConnectionStatus.placeholderText(state: nil, connection: .startingDaemon, now: .now),
      "Starting timer…",
    )
  }

  func testPlaceholderTextReconnecting() {
    XCTAssertEqual(
      ConnectionStatus.placeholderText(state: nil, connection: .reconnecting(attempt: 2), now: .now),
      "Reconnecting…",
    )
  }

  func testPlaceholderTextConnected() {
    XCTAssertEqual(
      ConnectionStatus.placeholderText(state: nil, connection: .connected, now: .now),
      "Throwntom",
    )
  }
}

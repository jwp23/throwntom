import Foundation
import XCTest
@testable import ThrowntomClient

final class ConnectionStatusTests: XCTestCase {
    func testNilStateConnecting() {
        XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connecting, now: .now), "Throwntom…")
    }

    func testNilStateStartingDaemon() {
        XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .startingDaemon, now: .now), "Starting timer…")
    }

    func testNilStateReconnecting() {
        XCTAssertEqual(
            ConnectionStatus.text(state: nil, connection: .reconnecting(attempt: 2), now: .now),
            "Throwntom…"
        )
    }

    func testNilStateConnected() {
        XCTAssertEqual(ConnectionStatus.text(state: nil, connection: .connected, now: .now), "Throwntom")
    }
}

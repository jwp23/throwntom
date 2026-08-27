import XCTest
@testable import ThrowntomClient

@MainActor
final class TickerTests: XCTestCase {
    func testStartPublishesLaterTimes() async throws {
        let ticker = Ticker(interval: .milliseconds(10))
        defer { ticker.stop() }
        let before = ticker.now
        ticker.start()
        try await waitUntil { ticker.now > before }
    }

    /// A second start() must adopt the running loop: if it started a rival one, the single
    /// stop() below would cancel only the first and the clock would keep moving.
    func testSecondStartKeepsTheRunningLoop() async throws {
        let ticker = Ticker(interval: .milliseconds(10))
        defer { ticker.stop() }
        ticker.start()
        ticker.start()
        let before = ticker.now
        try await waitUntil { ticker.now > before }

        ticker.stop()
        let last = ticker.now
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ticker.now, last)
    }
}

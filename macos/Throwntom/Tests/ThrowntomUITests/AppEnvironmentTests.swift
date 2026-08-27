import Foundation
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

@MainActor
final class AppEnvironmentTests: XCTestCase {
    func testStartFeedsDaemonFramesFromTheInjectedTransport() async throws {
        let environment = AppEnvironment(transport: try StubTransport(states: [makeState(phase: .work)]))
        defer { shutDown(environment) }

        environment.start()

        try await waitUntil { environment.client.connection == .connected }
        XCTAssertEqual(environment.client.state?.state, .work)
    }

    func testStartRunsTheCountdownClock() async throws {
        let environment = AppEnvironment(
            transport: try StubTransport(states: []),
            ticker: Ticker(interval: .milliseconds(10)))
        defer { shutDown(environment) }
        let before = environment.ticker.now

        environment.start()

        try await waitUntil { environment.ticker.now > before }
    }

    func testLiveEnvironmentStartsDisconnectedWithNoTasks() {
        let environment = AppEnvironment.live()

        XCTAssertEqual(environment.client.connection, .connecting)
        XCTAssertNil(environment.client.state)
        XCTAssertTrue(environment.model.tasks.active.isEmpty)
    }

    private func shutDown(_ environment: AppEnvironment) {
        environment.client.stop()
        environment.ticker.stop()
    }
}

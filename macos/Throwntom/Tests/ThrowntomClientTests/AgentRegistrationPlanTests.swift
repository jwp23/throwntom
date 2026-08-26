import XCTest
@testable import ThrowntomClient

final class AgentRegistrationPlanTests: XCTestCase {
    func testEnabledButUnreachableReloadsByUnregisterThenRegister() {
        XCTAssertEqual(AgentRegistrationPlan.steps(for: .enabled), [.unregister, .register])
    }

    func testUnregisteredStatesJustRegister() {
        for status in [AgentStatus.notRegistered, .notFound, .requiresApproval] {
            XCTAssertEqual(AgentRegistrationPlan.steps(for: status), [.register], "\(status)")
        }
    }
}

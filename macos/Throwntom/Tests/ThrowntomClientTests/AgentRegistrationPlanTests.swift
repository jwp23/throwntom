import XCTest
@testable import ThrowntomClient

final class AgentRegistrationPlanTests: XCTestCase {
    func testEnabledButUnreachableReloadsByUnregisterThenRegister() {
        XCTAssertEqual(AgentRegistrationPlan.steps(for: .enabled), [.unregister, .register])
    }

    func testUnregisteredStatesJustRegister() {
        for status in [AgentStatus.notRegistered, .notFound, .requiresApproval, .unknown] {
            XCTAssertEqual(AgentRegistrationPlan.steps(for: status), [.register], "\(status)")
        }
    }

    func testExecuteRunsEveryStepOfThePlanInOrder() throws {
        var performed: [AgentRegistrationStep] = []
        try AgentRegistrationPlan.execute(for: .enabled) { performed.append($0) }
        XCTAssertEqual(performed, [.unregister, .register])
    }

    func testFailedUnregisterIsDeferredWhenRegisterSucceeds() throws {
        var performed: [AgentRegistrationStep] = []
        try AgentRegistrationPlan.execute(for: .enabled) { step in
            performed.append(step)
            if step == .unregister { throw StaleEntry() }
        }
        XCTAssertEqual(performed, [.unregister, .register])
    }

    func testDeferredUnregisterErrorWinsWhenRegisterAlsoFails() {
        XCTAssertThrowsError(
            try AgentRegistrationPlan.execute(for: .enabled) { step in
                throw step == .unregister ? StaleEntry() : RegisterRefused()
            }
        ) { error in
            XCTAssertTrue(error is StaleEntry, "\(error)")
        }
    }

    func testRegisterErrorSurfacesWhenNothingWasDeferred() {
        XCTAssertThrowsError(
            try AgentRegistrationPlan.execute(for: .notRegistered) { _ in throw RegisterRefused() }
        ) { error in
            XCTAssertTrue(error is RegisterRefused, "\(error)")
        }
    }

    func testStatusDescriptionNamesWhatTheUserMustDoNext() {
        let descriptions: [(status: AgentStatus, text: String)] = [
            (.enabled, "Timer agent enabled"),
            (.requiresApproval, "Timer agent needs approval in Login Items"),
            (.notRegistered, "Timer agent not registered"),
            (.notFound, "Timer agent plist not found in bundle"),
            (.unknown, "Timer agent status unknown"),
        ]
        for (status, expected) in descriptions {
            XCTAssertEqual(AgentRegistrationPlan.statusDescription(for: status), expected)
        }
    }

    func testLoginItemTogglesBetweenRegisterAndUnregister() {
        XCTAssertEqual(AgentRegistrationPlan.loginItemStep(isEnabled: true), .register)
        XCTAssertEqual(AgentRegistrationPlan.loginItemStep(isEnabled: false), .unregister)
    }
}

private struct StaleEntry: Error {}
private struct RegisterRefused: Error {}

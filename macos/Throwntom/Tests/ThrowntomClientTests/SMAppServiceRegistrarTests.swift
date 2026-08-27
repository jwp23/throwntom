import ServiceManagement
import XCTest
@testable import ThrowntomClient

/// Only the status translation is exercised here. `SMAppService.Status` values are inert
/// enum cases, so reading them registers nothing; the registrar's own register, unregister
/// and Login Items calls mutate the machine running the tests and stay untested.
final class SMAppServiceRegistrarTests: XCTestCase {
    func testFrameworkStatusTranslatesToPlanStatus() {
        let translations: [SMAppService.Status: AgentStatus] = [
            .enabled: .enabled,
            .requiresApproval: .requiresApproval,
            .notRegistered: .notRegistered,
            .notFound: .notFound,
        ]
        for (status, expected) in translations {
            XCTAssertEqual(AgentStatus(status), expected, "\(status)")
        }
    }
}

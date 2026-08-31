import ServiceManagement
import XCTest
@testable import ThrowntomClient

// MARK: - SMAppServiceRegistrarTests

/// The registrar is driven through fakes for both `LaunchAgentService` and `MainAppService`, so
/// no test here registers a launchd agent or touches Login Items. `SMAppService.Status` values
/// are inert enum cases, so translating them registers nothing either.
final class SMAppServiceRegistrarTests: XCTestCase {
  func testReloadUnregistersThenRegistersWhenAgentReportsEnabled() throws {
    let agent = FakeAgentService(status: .enabled)
    try SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
    XCTAssertEqual(agent.calls, [.unregister, .register])
  }

  func testStaleAgentThatRefusesUnregisterStillRegisters() throws {
    let agent = FakeAgentService(status: .enabled, unregisterError: StaleEntry())
    try SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
    XCTAssertEqual(agent.calls, [.unregister, .register])
  }

  /// The refused unregister is deliberately not thrown when the register that follows succeeds —
  /// but it is the trace of a stale BTM entry, and until now it was dropped without a word
  /// anywhere. Registering over it works today and stops working eventually, so the one moment
  /// the app knows about it is the moment worth recording.
  func testARefusedUnregisterIsRecordedEvenWhenRegisterSucceeds() throws {
    let recorder = LogRecorder()
    let agent = FakeAgentService(
      status: .enabled,
      unregisterError: NSError(domain: "SMAppServiceErrorDomain", code: 1),
    )

    try SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()

    XCTAssertEqual(agent.calls, [.unregister, .register])
    let entry = try recorder.onlyEntry()
    XCTAssertEqual(entry.area, .service)
    XCTAssertEqual(entry.message, "unregister the stale launch agent failed: SMAppServiceErrorDomain 1")
  }

  func testRefusedUnregisterIsReportedWhenRegisterAlsoFails() {
    let agent = FakeAgentService(
      status: .enabled,
      unregisterError: StaleEntry(),
      registerError: RegisterRefused(),
    )
    XCTAssertThrowsError(try SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()) {
      XCTAssertTrue($0 is StaleEntry, "\($0)")
    }
  }

  func testRegisterErrorSurfacesWhenThereWasNothingToUnregister() {
    let agent = FakeAgentService(status: .notRegistered, registerError: RegisterRefused())
    XCTAssertThrowsError(try SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()) {
      XCTAssertTrue($0 is RegisterRefused, "\($0)")
    }
    XCTAssertEqual(agent.calls, [.register])
  }

  func testStatusDescriptionNamesWhatTheUserMustDoNext() {
    let descriptions: [(status: AgentStatus, text: String)] = [
      (.enabled, "Timer agent enabled"),
      (.requiresApproval, "Timer agent needs approval in Login Items"),
      (.notRegistered, "Timer agent not registered"),
      (.notFound, "Timer agent plist not found in bundle"),
      (.unknown, "Timer agent status unknown"),
    ]
    for (status, text) in descriptions {
      let registrar = SMAppServiceRegistrar(agent: FakeAgentService(status: status))
      XCTAssertEqual(registrar.agentStatusDescription, text)
    }
  }

  func testLoginItemEnabledReflectsMainAppStatus() {
    let enabled = SMAppServiceRegistrar(mainApp: FakeMainAppService(status: .enabled))
    XCTAssertTrue(enabled.loginItemEnabled)

    let disabled = SMAppServiceRegistrar(mainApp: FakeMainAppService(status: .notRegistered))
    XCTAssertFalse(disabled.loginItemEnabled)
  }

  func testSetLoginItemTrueRegistersTheMainApp() throws {
    let mainApp = FakeMainAppService(status: .notRegistered)
    try SMAppServiceRegistrar(mainApp: mainApp).setLoginItem(true)
    XCTAssertEqual(mainApp.calls, [.register])
  }

  func testSetLoginItemFalseUnregistersTheMainApp() throws {
    let mainApp = FakeMainAppService(status: .enabled)
    try SMAppServiceRegistrar(mainApp: mainApp).setLoginItem(false)
    XCTAssertEqual(mainApp.calls, [.unregister])
  }

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

// MARK: - FakeAgentService

// `calls` is mutated only by the registrar under test on the test actor; LaunchAgentService requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
private final class FakeAgentService: LaunchAgentService, @unchecked Sendable {

  // MARK: Lifecycle

  init(status: AgentStatus, unregisterError: Error? = nil, registerError: Error? = nil) {
    self.status = status
    self.unregisterError = unregisterError
    self.registerError = registerError
  }

  // MARK: Internal

  let status: AgentStatus
  private(set) var calls = [AgentRegistrationStep]()

  func register() throws {
    calls.append(.register)
    if let registerError {
      throw registerError
    }
  }

  func unregister() throws {
    calls.append(.unregister)
    if let unregisterError {
      throw unregisterError
    }
  }

  // MARK: Private

  private let registerError: Error?
  private let unregisterError: Error?

}

// MARK: - FakeMainAppService

// `calls` is mutated only by the registrar under test on the test actor; MainAppService requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
private final class FakeMainAppService: MainAppService, @unchecked Sendable {

  // MARK: Lifecycle

  init(status: AgentStatus) {
    self.status = status
  }

  // MARK: Internal

  let status: AgentStatus
  private(set) var calls = [AgentRegistrationStep]()

  func register() throws {
    calls.append(.register)
  }

  func unregister() throws {
    calls.append(.unregister)
  }

}

// MARK: - StaleEntry

private struct StaleEntry: Error { }

// MARK: - RegisterRefused

private struct RegisterRefused: Error { }

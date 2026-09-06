import Foundation
import ServiceManagement
import XCTest
@testable import ThrowntomClient

// MARK: - SMAppServiceRegistrarTests

/// The registrar is driven through fakes for both `LaunchAgentService` and `MainAppService`, so
/// no test here registers a launchd agent or touches Login Items. `SMAppService.Status` values
/// are inert enum cases, so translating them registers nothing either.
final class SMAppServiceRegistrarTests: XCTestCase {
  func testReloadUnregistersThenRegistersWhenAgentReportsEnabled() async throws {
    let agent = FakeAgentService(status: .enabled)
    try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
    XCTAssertEqual(agent.calls, [.unregister, .register])
  }

  func testStaleAgentThatRefusesUnregisterStillRegisters() async throws {
    let agent = FakeAgentService(status: .enabled, unregisterError: StaleEntry())
    try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
    XCTAssertEqual(agent.calls, [.unregister, .register])
  }

  /// The refused unregister is deliberately not thrown when the register that follows succeeds,
  /// but it is the trace of a stale BTM entry. Registering over one works until it does not, so
  /// the moment the app learns of it is the only moment there is to record it.
  func testARefusedUnregisterIsRecordedEvenWhenRegisterSucceeds() async throws {
    let recorder = LogRecorder()
    let agent = FakeAgentService(
      status: .enabled,
      unregisterError: NSError(domain: "SMAppServiceErrorDomain", code: 1),
    )

    try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()

    XCTAssertEqual(agent.calls, [.unregister, .register])
    let entry = try recorder.onlyEntry()
    XCTAssertEqual(entry.area, .service)
    XCTAssertEqual(entry.message, "unregister the stale launch agent failed: SMAppServiceErrorDomain 1")
  }

  func testRefusedUnregisterIsReportedWhenRegisterAlsoFails() async {
    let agent = FakeAgentService(
      status: .enabled,
      unregisterError: StaleEntry(),
      registerError: RegisterRefused(),
    )
    do {
      try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
      XCTFail("a register that failed after a refused unregister has to report the refusal")
    } catch {
      XCTAssertTrue(error is StaleEntry, "\(error)")
    }
  }

  func testRegisterErrorSurfacesWhenThereWasNothingToUnregister() async {
    let agent = FakeAgentService(status: .notRegistered, registerError: RegisterRefused())
    do {
      try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()
      XCTFail("a refused register has to be reported")
    } catch {
      XCTAssertTrue(error is RegisterRefused, "\(error)")
    }
    XCTAssertEqual(agent.calls, [.register])
  }

  /// throwntom-339. `LaunchdAgentService` drives `launchctl` with `Process` and waits for it to
  /// exit, and a registration is up to four of those. On the main actor that is the window frozen
  /// for the length of a bootstrap, so the registrar's launchd calls have to leave it.
  @MainActor
  func testRegisteringTheAgentLeavesTheMainActor() async throws {
    let agent = FakeAgentService(status: .enabled)

    try await SMAppServiceRegistrar(agent: agent).ensureAgentRegistered()

    XCTAssertEqual(agent.calls, [.unregister, .register])
    XCTAssertEqual(agent.mainThreadCalls, [false, false], "launchctl was waited on where the window is drawn")
  }

  @MainActor
  func testStoppingTheAgentLeavesTheMainActor() async throws {
    let agent = FakeAgentService(status: .enabled)

    try await SMAppServiceRegistrar(agent: agent).stopAgent()

    XCTAssertEqual(agent.mainThreadCalls, [false], "launchctl was waited on where the window is drawn")
  }

  /// The ordering the main actor used to supply for nothing. While these calls held it, a user's
  /// Stop could not reach launchd in the middle of a registration; they no longer hold it, and
  /// `bootout` and `bootstrap` name one job, so a pair of them overlapping is not two operations
  /// but one undefined one.
  func testOneLaunchdCallNeverOverlapsAnother() async throws {
    let agent = OverlapWatchingAgentService()
    let registrar = SMAppServiceRegistrar(agent: agent)

    async let registering: Void = registrar.ensureAgentRegistered()
    async let stopping: Void = registrar.stopAgent()
    _ = try await (registering, stopping)

    XCTAssertFalse(agent.sawOverlap, "a Stop reached launchd in the middle of a registration")
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

// `calls` and `mainThreadCalls` are mutated one call at a time, serialized by AgentDriver's own
// isolation; nothing reads them until the `await` that ran the call has returned.
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

  /// Whether each launchd call arrived on the main thread; every one of them waits on a
  /// subprocess, so none of them may.
  private(set) var mainThreadCalls = [Bool]()

  func register() throws {
    calls.append(.register)
    mainThreadCalls.append(Thread.isMainThread)
    if let registerError {
      throw registerError
    }
  }

  func unregister() throws {
    calls.append(.unregister)
    mainThreadCalls.append(Thread.isMainThread)
    if let unregisterError {
      throw unregisterError
    }
  }

  // MARK: Private

  private let registerError: Error?
  private let unregisterError: Error?

}

// MARK: - OverlapWatchingAgentService

/// An agent whose launchd calls take long enough to catch another one arriving on top of them.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
private final class OverlapWatchingAgentService: LaunchAgentService, @unchecked Sendable {

  // MARK: Internal

  /// `.enabled` so a registration is the full unregister-then-register, which is the sequence a
  /// Stop has the most room to land inside.
  let status = AgentStatus.enabled

  var sawOverlap: Bool {
    lock.withLock { overlapped }
  }

  func register() throws {
    runOneCall()
  }

  func unregister() throws {
    runOneCall()
  }

  // MARK: Private

  private let lock = NSLock()
  private var inFlight = 0
  private var overlapped = false

  /// Blocks rather than sleeping on the clock: this stands in for `launchctl`, which is a
  /// subprocess waited on synchronously, and it is that wait the ordering has to survive.
  private func runOneCall() {
    lock.withLock {
      inFlight += 1
      overlapped = overlapped || inFlight > 1
    }
    Thread.sleep(forTimeInterval: 0.05)
    lock.withLock { inFlight -= 1 }
  }

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

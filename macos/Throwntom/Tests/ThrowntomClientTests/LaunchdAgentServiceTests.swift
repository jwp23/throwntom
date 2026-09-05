import XCTest

@testable import ThrowntomClient

final class LaunchdAgentServiceTests: XCTestCase {

  // MARK: Internal

  func testRegisterWritesThePlistForThisBundlesDaemon() throws {
    let service = makeService()
    try service.register()
    XCTAssertEqual(
      LaunchdAgentPlist.programPath(inPlistAt: LaunchdAgentPlist.url(inHome: home)),
      bundle.appendingPathComponent("Contents/MacOS/throwntomd").path,
    )
  }

  /// The stale job has to go before the new one is loaded, or bootstrap hits a label launchd
  /// already holds and the daemon an upgrade replaced keeps running.
  func testRegisterBootsTheOldJobOutBeforeBootstrappingTheNewOne() throws {
    let service = makeService()
    try service.register()
    XCTAssertEqual(calls.map(\.first), ["bootout", "bootstrap"])
  }

  func testRegisterReportsWhenLaunchdRefusesTheJob() throws {
    let service = makeService { $0.first == "bootstrap" ? 1 : 0 }
    XCTAssertThrowsError(try service.register()) { error in
      guard case LaunchdAgentError.launchctlFailed(let command, let status) = error else {
        return XCTFail("expected launchctlFailed, got \(error)")
      }
      XCTAssertEqual(command, "bootstrap")
      XCTAssertEqual(status, 1)
    }
  }

  /// A bootout for a job launchd does not have exits non-zero, and that is the ordinary case on
  /// a first install; only the bootstrap failing means the agent did not load.
  func testRegisterSucceedsWhenThereWasNoOldJobToBootOut() throws {
    let service = makeService { $0.first == "bootout" ? 3 : 0 }
    XCTAssertNoThrow(try service.register())
  }

  func testUnregisterUnloadsTheJobAndRemovesThePlist() throws {
    // print non-zero means launchd no longer has the job, which is what a bootout should leave.
    let service = makeService { $0.first == "print" ? 1 : 0 }
    try service.register()
    try service.unregister()
    XCTAssertFalse(FileManager.default.fileExists(atPath: LaunchdAgentPlist.url(inHome: home).path))
  }

  /// Stop is a user action. Reporting success while launchd still has the job would leave the
  /// timer running behind a UI that says it stopped.
  func testUnregisterReportsWhenTheJobIsStillLoadedAfterwards() throws {
    let service = makeService { $0.first == "print" ? 0 : 1 }
    try makeService { $0.first == "print" ? 1 : 0 }.register()
    XCTAssertThrowsError(try service.unregister())
  }

  // ADR-010: a stopped timer service stays stopped. The plist has RunAtLoad, so leaving it
  // behind would start the daemon again at the next login.
  func testUnregisterLeavesNothingToReloadTheDaemonAtLogin() throws {
    let service = makeService { $0.first == "print" ? 1 : 0 }
    try service.register()
    XCTAssertTrue(FileManager.default.fileExists(atPath: LaunchdAgentPlist.url(inHome: home).path))
    try service.unregister()
    XCTAssertNil(LaunchdAgentPlist.programPath(inPlistAt: LaunchdAgentPlist.url(inHome: home)))
  }

  /// Stopping a service that is already stopped is not a failure, and there is no plist to remove.
  func testUnregisterIsFineWhenNothingWasRegistered() {
    XCTAssertNoThrow(try makeService { $0.first == "print" ? 1 : 0 }.unregister())
  }

  func testABundleWithNoDaemonCannotBeRegistered() {
    let service = LaunchdAgentService(
      bundleURL: home.appendingPathComponent("Absent.app"),
      home: home,
      launchctl: record,
    )
    XCTAssertEqual(service.status, .notFound)
    XCTAssertThrowsError(try service.register())
  }

  func testAnAgentIsEnabledOnlyWhenItsPlistAndLoadedJobBothMatch() throws {
    let loaded = makeService { _ in 0 }
    try loaded.register()
    XCTAssertEqual(loaded.status, .enabled)

    let notLoaded = makeService { $0.first == "print" ? 1 : 0 }
    XCTAssertEqual(notLoaded.status, .notRegistered)
  }

  // MARK: Private

  private var calls = [[String]]()

  private lazy var home: URL = {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("agent-service-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }()

  private lazy var bundle: URL = {
    let url = home.appendingPathComponent("Throwntom.app")
    let binary = url.appendingPathComponent("Contents/MacOS/throwntomd")
    try? FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    FileManager.default.createFile(
      atPath: binary.path,
      contents: Data(),
      attributes: [.posixPermissions: 0o755],
    )
    return url
  }()

  private func makeService(_ exit: @escaping @Sendable ([String]) -> Int32 = { _ in 0 })
    -> LaunchdAgentService
  {
    LaunchdAgentService(bundleURL: bundle, home: home, launchctl: { [self] arguments in
      calls.append(arguments)
      return exit(arguments)
    })
  }

  private func record(_ arguments: [String]) -> Int32 {
    calls.append(arguments)
    return 0
  }

}

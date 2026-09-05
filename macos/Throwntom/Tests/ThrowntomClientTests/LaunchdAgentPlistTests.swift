import XCTest

@testable import ThrowntomClient

final class LaunchdAgentPlistTests: XCTestCase {

  // MARK: Internal

  func testProgramArgumentsIsTheAbsolutePathToTheDaemon() throws {
    let plist = try decode(LaunchdAgentPlist(programPath: "/Applications/Throwntom.app/Contents/MacOS/throwntomd").data())
    XCTAssertEqual(
      plist["ProgramArguments"] as? [String],
      ["/Applications/Throwntom.app/Contents/MacOS/throwntomd"],
    )
  }

  func testLabelMatchesTheAgentTheClientTalksTo() throws {
    let plist = try decode(LaunchdAgentPlist(programPath: "/tmp/throwntomd").data())
    XCTAssertEqual(plist["Label"] as? String, LaunchdAgentPlist.label)
  }

  func testTheDaemonStartsWithTheLoginSession() throws {
    let plist = try decode(LaunchdAgentPlist(programPath: "/tmp/throwntomd").data())
    XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
  }

  /// A second throwntomd that loses the single-instance lock exits 0 and stands down. Restarting
  /// it would put it straight back into the losing race, so KeepAlive must revive the daemon only
  /// when it fails, never when it chose to stop.
  func testACleanExitIsNotRestarted() throws {
    let plist = try decode(LaunchdAgentPlist(programPath: "/tmp/throwntomd").data())
    let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Bool])
    XCTAssertEqual(keepAlive["SuccessfulExit"], false)
  }

  func testTheProgramPathIsReadBackFromWhatWasWritten() throws {
    let written = LaunchdAgentPlist(programPath: "/Users/x/Throwntom.app/Contents/MacOS/throwntomd")
    XCTAssertEqual(
      LaunchdAgentPlist.programPath(inPlistAt: try write(written)),
      "/Users/x/Throwntom.app/Contents/MacOS/throwntomd",
    )
  }

  /// An upgrade replaces the bundle, and a plist naming the previous copy would keep launchd
  /// running a daemon the app is no longer part of. Reading it back is what detects that.
  func testAnUnreadableOrMissingPlistHasNoProgramPath() throws {
    let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("absent.plist")
    XCTAssertNil(LaunchdAgentPlist.programPath(inPlistAt: missing))

    let garbage = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("garbage-\(UUID().uuidString).plist")
    try Data("not a plist".utf8).write(to: garbage)
    defer { try? FileManager.default.removeItem(at: garbage) }
    XCTAssertNil(LaunchdAgentPlist.programPath(inPlistAt: garbage))
  }

  // MARK: Private

  private func decode(_ data: Data) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: data, format: nil)
    return try XCTUnwrap(object as? [String: Any])
  }

  private func write(_ plist: LaunchdAgentPlist) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("agent-\(UUID().uuidString).plist")
    try plist.data().write(to: url)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

}

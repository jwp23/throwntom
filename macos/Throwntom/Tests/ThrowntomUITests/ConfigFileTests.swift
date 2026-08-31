import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// "Open Config File…" hands the file to whatever edits text. macOS answers whether anything took
/// it, and a menu item that silently does nothing is the same class of failure as a beep with no
/// record behind it.
@MainActor
final class ConfigFileTests: XCTestCase {

  func testAConfigFileNothingWillOpenIsRecorded() {
    let recorder = LogRecorder()

    ConfigFile.open { _ in false }

    XCTAssertEqual(recorder.entries.first?.area, .service)
    XCTAssertEqual(recorder.messages, ["open the config file failed: no application accepted it"])
  }

  func testAConfigFileThatOpensRecordsNothing() {
    let recorder = LogRecorder()

    ConfigFile.open { _ in true }

    XCTAssertEqual(recorder.entries, [])
  }

  func testTheFileHandedOverIsTheOneTheDaemonReads() {
    var opened: URL?

    ConfigFile.open { url in
      opened = url
      return true
    }

    XCTAssertEqual(opened, DaemonPaths.configFileToOpen())
  }

}

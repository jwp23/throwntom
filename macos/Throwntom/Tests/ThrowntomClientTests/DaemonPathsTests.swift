import XCTest
@testable import ThrowntomClient

final class DaemonPathsTests: XCTestCase {
    func testConfigFileToOpenPrefersTheFileOverItsDirectory() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tt-paths-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = DaemonPaths.configDirectory(inHome: home)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertEqual(DaemonPaths.configFileToOpen(inHome: home), directory, "no config file yet, reveal the folder")
        let file = directory.appendingPathComponent("config.toml")
        try Data().write(to: file)
        XCTAssertEqual(DaemonPaths.configFileToOpen(inHome: home), file)
    }

    func testSocketLivesInTheConfigDirectory() {
        XCTAssertTrue(DaemonPaths.socketPath.hasSuffix(".config/throwntom/daemon.sock"), DaemonPaths.socketPath)
    }
}

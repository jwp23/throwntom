import Foundation
import XCTest
@testable import ThrowntomClient

struct TimeoutError: Error {}

/// Polls `condition` every 20 ms until it holds or `timeout` seconds pass.
/// MainActor-isolated so tests can read DaemonClient's MainActor properties inside `condition`.
@MainActor
func waitUntil(timeout: Double = 5, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    throw TimeoutError()
}

/// Thread-safe log of decoded DaemonState frames received on a background task.
final class FrameLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _frames: [DaemonState] = []
    private var _error: Error?

    var frames: [DaemonState] { lock.withLock { _frames } }
    var error: Error? { lock.withLock { _error } }

    func append(_ s: DaemonState) { lock.withLock { _frames.append(s) } }
    func fail(_ e: Error) { lock.withLock { _error = e } }

    /// Consumes the stream until it ends; returns immediately.
    func consume(_ stream: AsyncThrowingStream<Data, Error>) -> Task<Void, Never> {
        Task {
            do {
                for try await frame in stream {
                    append(try DaemonJSON.decoder.decode(DaemonState.self, from: frame))
                }
            } catch {
                fail(error)
            }
        }
    }
}

/// Builds throwntomd once per test process and runs it against a private HOME under /tmp.
final class DaemonHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let binary: URL = {
        let out = repoRoot.appendingPathComponent("macos/Throwntom/.build/throwntomd")
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        build.arguments = ["go", "build", "-o", out.path, "./cmd/throwntomd"]
        build.currentDirectoryURL = repoRoot
        try! build.run()
        build.waitUntilExit()
        precondition(build.terminationStatus == 0, "go build ./cmd/throwntomd failed")
        return out
    }()

    let home: URL
    private var process: Process?

    var socketPath: String { home.appendingPathComponent(".config/throwntom/daemon.sock").path }

    init() throws {
        home = URL(fileURLWithPath: "/tmp/tt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func start() async throws {
        let p = Process()
        p.executableURL = Self.binary
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p
        try await waitUntil { FileManager.default.fileExists(atPath: socketPath) }
    }

    func stop() {
        guard let p = process else { return }
        p.terminate()
        p.waitUntilExit()
        process = nil
    }

    func cleanup() {
        stop()
        try? FileManager.default.removeItem(at: home)
    }
}

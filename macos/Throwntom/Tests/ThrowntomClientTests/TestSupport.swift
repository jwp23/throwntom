import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - TimeoutError

/// A wait that never came true, described in full. A hung test used to surface a bare
/// `CancellationError` attributed to whichever line happened to be sleeping, naming neither the
/// wait nor what it wanted; this carries both, so the message alone identifies the failure.
struct TimeoutError: Error, CustomStringConvertible {

  // MARK: Lifecycle

  init(waitingFor what: String, timeout: Double, cancelled: Bool, file: StaticString, line: UInt) {
    let ending = cancelled ? "cancelled after" : "timed out after"
    let source = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
    description = "\(ending) \(timeout)s waiting for \(what) (\(source):\(line))"
  }

  // MARK: Internal

  let description: String

}

// MARK: - GoBuildError

struct GoBuildError: Error, CustomStringConvertible {
  let description: String
}

/// Waits for `condition` and fails the test at the call site, naming `what`, if it never holds.
/// MainActor-isolated so tests can read DaemonClient's MainActor properties inside `condition`.
@MainActor
func waitUntil(
  _ what: String,
  timeout: Double = 5,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ condition: () -> Bool,
) async throws {
  guard let failure = await pollUntil(what, timeout: timeout, file: file, line: line, condition) else {
    return
  }
  XCTFail(failure.description, file: file, line: line)
  throw failure
}

/// The wait without the reporting: polls `condition` every 20 ms and returns nil once it holds,
/// or the failure to report if it never does. Separate from `waitUntil` so the suite can assert
/// on what a failed wait says without XCTest recording the very failure under test.
@MainActor
func pollUntil(
  _ what: String,
  timeout: Double = 5,
  file: StaticString = #filePath,
  line: UInt = #line,
  _ condition: () -> Bool,
) async -> TimeoutError? {
  let deadline = Date.now.addingTimeInterval(timeout)
  while Date.now < deadline {
    if condition() {
      return nil
    }
    do {
      try await Task.sleep(for: .milliseconds(20))
    } catch {
      // The enclosing test was cancelled, which for a MainActor test means it overran. Reporting
      // that as this wait is the point: the cancellation alone names neither wait nor condition.
      return TimeoutError(waitingFor: what, timeout: timeout, cancelled: true, file: file, line: line)
    }
  }
  return TimeoutError(waitingFor: what, timeout: timeout, cancelled: false, file: file, line: line)
}

// MARK: - FrameLog

/// Thread-safe log of decoded DaemonState frames received on a background task.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class FrameLog: @unchecked Sendable {

  // MARK: Internal

  var frames: [DaemonState] {
    lock.withLock { _frames }
  }

  var error: Error? {
    lock.withLock { _error }
  }

  func append(_ s: DaemonState) {
    lock.withLock { _frames.append(s) }
  }

  func fail(_ e: Error) {
    lock.withLock { _error = e }
  }

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

  // MARK: Private

  private let lock = NSLock()
  private var _frames = [DaemonState]()
  private var _error: Error?

}

// MARK: - DaemonHarness

/// Builds throwntomd once per test process and runs it against a private HOME under /tmp.
/// The HOME carries a config whose schedule is active every day from midnight, so the morning
/// reminder is outstanding whenever the daemon starts rather than only on weekday afternoons.
final class DaemonHarness {

  // MARK: Lifecycle

  init() throws {
    home = URL(fileURLWithPath: "/tmp/tt-\(UUID().uuidString.prefix(8))")
    let configDir = home.appendingPathComponent(".config/throwntom")
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    try Self.alwaysActiveConfig.write(
      to: configDir.appendingPathComponent("config.toml"),
      atomically: true,
      encoding: .utf8,
    )
  }

  // MARK: Internal

  static let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

  let home: URL

  var socketPath: String {
    home.appendingPathComponent(".config/throwntom/daemon.sock").path
  }

  /// Builds throwntomd once per test process; every later call replays the same result.
  static func binary() throws -> URL {
    try binaryResult.get()
  }

  func start() async throws {
    let p = Process()
    p.executableURL = try Self.binary()
    var env = ProcessInfo.processInfo.environment
    env["HOME"] = home.path
    p.environment = env
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    process = p
    try await waitUntil("the daemon to open its socket") { FileManager.default.fileExists(atPath: socketPath) }
  }

  /// Asks the daemon to exit and escalates to SIGKILL rather than waiting on it forever,
  /// so a wedged daemon fails one test instead of hanging the whole suite.
  func stop() {
    guard let p = process else { return }
    p.terminate()
    if !Self.waitForExit(p, timeout: 5) {
      kill(p.processIdentifier, SIGKILL)
    }
    p.waitUntilExit()
    process = nil
  }

  func cleanup() {
    stop()
    try? FileManager.default.removeItem(at: home)
  }

  // MARK: Private

  private static let alwaysActiveConfig = """
    [[schedule]]
    days = ["weekday", "weekend"]
    time = "00:00"

    """

  private static let binaryResult: Result<URL, Error> = {
    let out = repoRoot.appendingPathComponent("macos/Throwntom/.build/throwntomd")
    let build = Process()
    build.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    build.arguments = ["go", "build", "-o", out.path, "./cmd/throwntomd"]
    build.currentDirectoryURL = repoRoot
    do {
      try build.run()
    } catch {
      return .failure(error)
    }
    build.waitUntilExit()
    guard build.terminationStatus == 0 else {
      return .failure(GoBuildError(description: "go build ./cmd/throwntomd failed"))
    }
    return .success(out)
  }()

  private var process: Process?

  private static func waitForExit(_ p: Process, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !p.isRunning {
        return true
      }
      Thread.sleep(forTimeInterval: 0.02)
    }
    return false
  }

}

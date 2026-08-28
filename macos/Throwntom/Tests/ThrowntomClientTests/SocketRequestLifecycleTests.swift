import XCTest
@testable import ThrowntomClient

// MARK: - SocketRequestLifecycleTests

/// Covers what `request` does when the peer accepts the connection but never answers.
final class SocketRequestLifecycleTests: XCTestCase {

  // MARK: Internal

  override func setUpWithError() throws {
    server = try StalledSocketServer()
  }

  override func tearDown() {
    server?.stop()
    server = nil
  }

  func testRequestTimesOutWhenPeerNeverReplies() async throws {
    let server = try XCTUnwrap(server)
    let timeout = Duration.milliseconds(150)
    let transport = UnixSocketTransport(socketPath: server.path, requestTimeout: timeout)
    let started = Date()
    do {
      _ = try await transport.request("GET", "/v1/state", body: nil)
      XCTFail("expected a timeout error")
    } catch let error as DaemonError {
      XCTAssertEqual(error, .timedOut(after: timeout))
    }
    XCTAssertLessThan(Date().timeIntervalSince(started), 2)
  }

  func testCancellingRequestUnblocksTheCaller() async throws {
    let server = try XCTUnwrap(server)
    let transport = UnixSocketTransport(socketPath: server.path)
    let outcome = RequestOutcome()
    let request = Task {
      do {
        _ = try await transport.request("GET", "/v1/state", body: nil)
        outcome.finish(nil)
      } catch {
        outcome.finish(error)
      }
    }

    // Let the request reach its pending receive before cancelling it.
    try await Task.sleep(for: .milliseconds(200))
    request.cancel()

    try await waitUntil(timeout: 2) { outcome.isFinished }
    XCTAssertTrue(outcome.error is CancellationError, "unexpected \(String(describing: outcome.error))")
  }

  // MARK: Private

  private var server: StalledSocketServer?

}

// MARK: - RequestOutcome

/// Thread-safe record of how a request Task ended, readable from the test's actor.
private final class RequestOutcome: @unchecked Sendable {

  // MARK: Internal

  var error: Error? {
    lock.withLock { _error }
  }

  var isFinished: Bool {
    lock.withLock { _isFinished }
  }

  func finish(_ error: Error?) {
    lock.withLock {
      _error = error
      _isFinished = true
    }
  }

  // MARK: Private

  private let lock = NSLock()
  private var _error: Error?
  private var _isFinished = false

}

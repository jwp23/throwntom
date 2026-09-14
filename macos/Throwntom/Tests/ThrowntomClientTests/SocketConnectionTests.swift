import XCTest
@testable import ThrowntomClient

// MARK: - SocketConnectionTests

/// Covers `SocketConnection` directly: what each call resolves to, and what it leaves behind.
/// `UnixSocketTransportTests` drives the same code through a real daemon, which says nothing
/// about the failure and cancellation paths a healthy daemon never takes.
///
/// Every wait here is bounded. A call that never resumes has to fail its test on a deadline,
/// because a test that waited for it instead would hang the whole suite.
final class SocketConnectionTests: XCTestCase {

  // MARK: Internal

  override func setUpWithError() throws {
    server = try StalledSocketServer()
  }

  override func tearDown() {
    server?.stop()
    server = nil
  }

  func testOpenResolvesWhenThePeerAcceptsTheConnection() throws {
    let connection = SocketConnection(path: try acceptingPath())
    defer { connection.close() }

    let opened = outcome(of: "open") { try await connection.open() }

    assertSucceeded(opened, "open against a peer that accepts")
  }

  func testSendFailsOnceTheConnectionIsClosed() throws {
    let connection = try openedConnection()
    connection.close()

    let sent = outcome(of: "send") { try await connection.send(Data([0x41])) }

    assertTransportFailure(sent, "send on a closed connection")
  }

  func testReceiveFailsOnceTheConnectionIsClosed() throws {
    let connection = try openedConnection()
    connection.close()

    let received = outcome(of: "receive") { try await connection.receive() }

    assertTransportFailure(received, "receive on a closed connection")
  }

  /// A refused open parks NWConnection in `.waiting`, where it retries the socket forever. The
  /// call reports that as a failure and tears the connection down, so nothing is left dialling.
  func testAFailedOpenLeavesNothingDialling() {
    let connection = SocketConnection(path: "/tmp/tt-missing-\(UUID().uuidString.prefix(8)).sock")
    defer { connection.close() }
    let opened = outcome(of: "open", within: 5) { try await connection.open() }
    assertTransportFailure(opened, "open of a missing socket")

    let received = outcome(of: "receive") { try await connection.receive() }

    assertTransportFailure(received, "receive after a failed open")
  }

  /// Cancelling reports the cancellation, not whichever socket error closing the connection
  /// raises: the close is what the caller asked for, so it is not what the caller hears about.
  func testCancellingAPendingReceiveReportsTheCancellation() throws {
    let connection = try openedConnection()
    defer { connection.close() }
    let receiving = pendingReceive(on: connection)

    receiving.cancel()

    assertCancelled(receiving.outcome(within: deadline), "the cancelled receive")
  }

  /// Cancelling also closes the connection: the caller is gone, so the socket goes with it.
  func testCancellingAPendingReceiveClosesTheConnection() throws {
    let connection = try openedConnection()
    defer { connection.close() }
    let receiving = pendingReceive(on: connection)
    receiving.cancel()
    XCTAssertNotNil(receiving.outcome(within: deadline), "the cancelled receive never finished")

    let afterwards = outcome(of: "receive") { try await connection.receive() }

    assertTransportFailure(afterwards, "receive after a cancelled receive")
  }

  /// A cancellation that lands before the call suspends still resumes it: the result arrives
  /// before there is a continuation to deliver it to, and is delivered as soon as there is one.
  func testACallStartedInACancelledTaskReportsTheCancellation() throws {
    let connection = SocketConnection(path: try acceptingPath())
    defer { connection.close() }
    let receiving = RunningOperation {
      // Sleeping until cancelled is what puts the cancellation ahead of `receive`: the task
      // cannot reach the call until it has been cancelled.
      try? await Task.sleep(for: .seconds(30))
      return try await connection.receive()
    }

    receiving.cancel()

    assertCancelled(receiving.outcome(within: deadline), "the receive in a cancelled task")
  }

  /// A cancellation that lands first also stops the call from starting: the socket work never
  /// runs, so a peer that would have accepted the connection never sees one.
  func testACallStartedInACancelledTaskNeverDialsThePeer() throws {
    let peer = try XCTUnwrap(server, "the stalled peer failed to start")
    let connection = SocketConnection(path: peer.path)
    defer { connection.close() }
    let opening = RunningOperation {
      try? await Task.sleep(for: .seconds(30))
      try await connection.open()
    }

    opening.cancel()

    assertCancelled(opening.outcome(within: deadline), "the open in a cancelled task")
    // A dial that should never have happened lands within milliseconds over a Unix socket.
    Thread.sleep(forTimeInterval: 0.2)
    XCTAssertEqual(peer.acceptedConnections, 0, "the cancelled open dialled the peer anyway")
  }

  // MARK: Private

  /// How long any call here is given before the test reports it as never having finished.
  private let deadline: TimeInterval = 2

  private var server: StalledSocketServer?

  /// The path of a peer that accepts connections and then says nothing.
  private func acceptingPath(file: StaticString = #filePath, line: UInt = #line) throws -> String {
    try XCTUnwrap(server, "the stalled peer failed to start", file: file, line: line).path
  }

  private func openedConnection(file: StaticString = #filePath, line: UInt = #line) throws -> SocketConnection {
    let connection = SocketConnection(path: try acceptingPath(file: file, line: line))
    let opened = outcome(of: "open", file: file, line: line) { try await connection.open() }
    assertSucceeded(opened, "open against a peer that accepts", file: file, line: line)
    return connection
  }

  /// A receive that the peer will never answer, so it is still pending when the test cancels it.
  private func pendingReceive(
    on connection: SocketConnection,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) -> RunningOperation<Data?> {
    let receiving = RunningOperation { try await connection.receive() }
    XCTAssertNil(receiving.outcome(within: 0.2), "the peer never replies, so the receive is pending", file: file, line: line)
    return receiving
  }

  /// Runs `work` and returns how it ended, or nil — having failed the test — when it had not
  /// ended within `within` seconds.
  private func outcome<T: Sendable>(
    of what: String,
    within limit: TimeInterval? = nil,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ work: @escaping @Sendable () async throws -> T,
  ) -> Result<T, Error>? {
    let limit = limit ?? deadline
    guard let outcome = RunningOperation(work).outcome(within: limit) else {
      XCTFail("\(what) had not finished \(limit)s after it started", file: file, line: line)
      return nil
    }
    return outcome
  }

  private func assertSucceeded<T>(
    _ outcome: Result<T, Error>?,
    _ what: String,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    guard let outcome else { return }
    XCTAssertNoThrow(try outcome.get(), what, file: file, line: line)
  }

  private func assertTransportFailure<T>(
    _ outcome: Result<T, Error>?,
    _ what: String,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    guard let outcome else { return }
    XCTAssertThrowsError(try outcome.get(), what, file: file, line: line) { error in
      guard case DaemonError.transport = error else {
        return XCTFail("\(what) failed with \(error), not a transport error", file: file, line: line)
      }
    }
  }

  private func assertCancelled<T>(
    _ outcome: Result<T, Error>?,
    _ what: String,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    guard let outcome else {
      return XCTFail("\(what) never finished", file: file, line: line)
    }
    XCTAssertThrowsError(try outcome.get(), what, file: file, line: line) { error in
      guard error is CancellationError else {
        return XCTFail("\(what) failed with \(error), not a cancellation", file: file, line: line)
      }
    }
  }

}

// MARK: - RunningOperation

/// One socket call running on a task of its own, with bounded ways to observe it. Bounded is
/// the point: a call that never resumes is reported by its deadline, and the test finishes.
// Every mutable member is read and written under `condition`.
// swiftlint:disable:next no_unchecked_sendable
private final class RunningOperation<T: Sendable>: @unchecked Sendable {

  // MARK: Lifecycle

  init(_ work: @escaping @Sendable () async throws -> T) {
    task = Task {
      do {
        self.settle(.success(try await work()))
      } catch {
        self.settle(.failure(error))
      }
    }
  }

  // MARK: Internal

  /// How the call ended, or nil when it had not ended within `limit` seconds.
  func outcome(within limit: TimeInterval) -> Result<T, Error>? {
    let end = Date().addingTimeInterval(limit)
    condition.lock()
    defer { condition.unlock() }
    while result == nil, Date() < end {
      condition.wait(until: end)
    }
    return result
  }

  /// Cancels on a thread of its own, because cancellation runs the connection's cancellation
  /// handler on whichever thread asks for it, and the test's thread has a deadline to keep.
  func cancel() {
    let task = task
    Thread.detachNewThread { task?.cancel() }
  }

  // MARK: Private

  private let condition = NSCondition()
  private var result: Result<T, Error>?
  private var task: Task<Void, Never>?

  private func settle(_ outcome: Result<T, Error>) {
    condition.lock()
    result = outcome
    condition.broadcast()
    condition.unlock()
  }

}

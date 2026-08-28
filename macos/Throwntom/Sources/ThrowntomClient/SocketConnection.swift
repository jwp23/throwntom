import Foundation
import Network

// MARK: - SocketConnection

/// One NWConnection to a Unix socket, exposed as async open/send/receive.
/// Every call honours Task cancellation: the connection is closed and the caller resumes immediately.
// NWConnection serialises its own callbacks on `queue`; every other member is immutable.
// swiftlint:disable:next no_unchecked_sendable
final class SocketConnection: @unchecked Sendable {

  // MARK: Lifecycle

  init(path: String) {
    connection = NWConnection(to: .unix(path: path), using: .tcp)
  }

  // MARK: Internal

  /// Resolves once the connection is ready. A missing or refused socket parks NWConnection in
  /// `.waiting`, which is reported as a failure so callers can retry with backoff.
  func open() async throws {
    try await perform { (gate: ResumeOnce<Void>) in
      connection.stateUpdateHandler = openStateHandler(gate: gate)
      connection.start(queue: queue)
    }
  }

  func send(_ data: Data) async throws {
    try await perform { (gate: ResumeOnce<Void>) in
      connection.send(content: data, completion: .contentProcessed { error in
        if let error {
          gate.finish(.failure(DaemonError.transport(String(describing: error))))
        } else {
          gate.finish(.success(()))
        }
      })
    }
  }

  /// Returns the next bytes, an empty Data when nothing arrived yet, or nil at end of stream.
  func receive() async throws -> Data? {
    try await perform { (gate: ResumeOnce<Data?>) in
      connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
        if let error {
          gate.finish(.failure(DaemonError.transport(String(describing: error))))
        } else if let data, !data.isEmpty {
          gate.finish(.success(data))
        } else if isComplete {
          gate.finish(.success(nil))
        } else {
          gate.finish(.success(Data()))
        }
      }
    }
  }

  func close() {
    connection.cancel()
  }

  // MARK: Private

  private let connection: NWConnection
  private let queue = DispatchQueue(label: "throwntom.socket")

  /// Builds the `stateUpdateHandler` for a pending `open()` call.
  private func openStateHandler(gate: ResumeOnce<Void>) -> @Sendable (NWConnection.State) -> Void {
    { [connection] state in
      switch state {
      case .ready:
        gate.finish(.success(()))

      case .waiting(let error),
           .failed(let error):
        // Only tear the connection down while `open` is still pending; the handler stays
        // installed afterwards, and a later state change belongs to an in-flight receive.
        if gate.finish(.failure(DaemonError.transport(String(describing: error)))) {
          connection.cancel()
        }

      case .cancelled:
        gate.finish(.failure(DaemonError.transport("connection cancelled")))

      default:
        break
      }
    }
  }

  /// Runs one Network.framework operation as a cancellable async call. Cancellation resumes the
  /// caller with `CancellationError` before closing the connection, so the reported error is the
  /// cancellation rather than whichever socket error the close happens to produce.
  private func perform<T>(_ operation: (ResumeOnce<T>) -> Void) async throws -> T {
    let gate = ResumeOnce<T>()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        guard gate.attach(continuation) else { return }
        operation(gate)
      }
    } onCancel: { [self] in
      gate.finish(.failure(CancellationError()))
      close()
    }
  }

}

// MARK: - ResumeOnce

/// Resumes a continuation exactly once, no matter how many terminal states NWConnection reports,
/// and copes with cancellation arriving before the continuation has been installed.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
private final class ResumeOnce<T>: @unchecked Sendable {

  // MARK: Internal

  /// Installs the continuation. Returns false when a result already arrived and was delivered,
  /// meaning the caller must not start the underlying operation.
  func attach(_ continuation: CheckedContinuation<T, Error>) -> Bool {
    lock.lock()
    guard let result = resultBeforeAttach else {
      self.continuation = continuation
      lock.unlock()
      return true
    }
    isFinished = true
    lock.unlock()
    continuation.resume(with: result)
    return false
  }

  /// Delivers `result` unless the call is already settled. Returns true when this call settled it.
  @discardableResult
  func finish(_ result: Result<T, Error>) -> Bool {
    lock.lock()
    guard !isFinished, resultBeforeAttach == nil else {
      lock.unlock()
      return false
    }
    guard let continuation else {
      resultBeforeAttach = result
      lock.unlock()
      return true
    }
    isFinished = true
    self.continuation = nil
    lock.unlock()
    continuation.resume(with: result)
    return true
  }

  // MARK: Private

  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var resultBeforeAttach: Result<T, Error>?
  private var isFinished = false

}

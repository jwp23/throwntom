import Foundation
import Network

/// One NWConnection to a Unix socket, exposed as async open/send/receive.
/// Every call honours Task cancellation: the connection is closed and the caller resumes immediately.
final class SocketConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "throwntom.socket")

    init(path: String) {
        connection = NWConnection(to: .unix(path: path), using: .tcp)
    }

    /// Resolves once the connection is ready. A missing or refused socket parks NWConnection in
    /// `.waiting`, which is reported as a failure so callers can retry with backoff.
    func open() async throws {
        try await perform { (gate: ResumeOnce<Void>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    gate.finish(.success(()))
                case .waiting(let error), .failed(let error):
                    connection.cancel()
                    gate.finish(.failure(DaemonError.transport(String(describing: error))))
                case .cancelled:
                    gate.finish(.failure(DaemonError.transport("connection cancelled")))
                default:
                    break
                }
            }
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

/// Resumes a continuation exactly once, no matter how many terminal states NWConnection reports,
/// and copes with cancellation arriving before the continuation has been installed.
private final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var resultBeforeAttach: Result<T, Error>?
    private var isFinished = false

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

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !isFinished else { return lock.unlock() }
        guard let continuation else {
            resultBeforeAttach = result
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

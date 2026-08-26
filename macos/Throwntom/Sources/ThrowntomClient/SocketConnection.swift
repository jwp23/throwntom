import Foundation
import Network

/// One NWConnection to a Unix socket, exposed as async open/send/receive.
final class SocketConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "throwntom.socket")

    init(path: String) {
        connection = NWConnection(to: .unix(path: path), using: .tcp)
    }

    /// Resolves once the connection is ready. A missing or refused socket parks NWConnection in
    /// `.waiting`, which is reported as a failure so callers can retry with backoff.
    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce()
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .waiting(let error), .failed(let error):
                    once.run {
                        connection.cancel()
                        continuation.resume(throwing: DaemonError.transport(String(describing: error)))
                    }
                case .cancelled:
                    once.run { continuation.resume(throwing: DaemonError.transport("connection cancelled")) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DaemonError.transport(String(describing: error)))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Returns the next bytes, an empty Data when nothing arrived yet, or nil at end of stream.
    func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: DaemonError.transport(String(describing: error)))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func close() {
        connection.cancel()
    }
}

/// Guards a continuation against NWConnection reporting more than one terminal state.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}

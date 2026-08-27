import Foundation
@testable import ThrowntomClient
@testable import ThrowntomUI

struct TimeoutError: Error {}

extension MenuModel {
    /// Every item in the menu, ignoring where the separators fall.
    var items: [MenuItem<Action>] { groups.flatMap { $0 } }

    func item(for action: Action) -> MenuItem<Action>? {
        items.first { $0.action == action }
    }
}

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

/// Writes the daemon's wire format: snake_case keys and RFC3339 timestamps. `DaemonJSON.encoder`
/// is the app's own encoder and emits numeric dates the client's decoder rejects.
let daemonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

func makeState(
    phase: DaemonState.Phase = .idle,
    morningPending: Bool = false,
    nextStage: DaemonState.NextStage? = nil,
    focusedTaskIds: [Int] = []
) -> DaemonState {
    DaemonState(
        state: phase, phaseEndAt: nil, pausedRemaining: 0, completedToday: 0,
        workSessionsInBlock: 0, longBreakEvery: 4, nextStage: nextStage,
        morningPending: morningPending, snoozeUntil: nil, statusLine: phase.displayName,
        focusedTaskIds: focusedTaskIds)
}

func makeTask(id: Int, description: String = "task", done: Bool = false) -> TaskItem {
    TaskItem(id: id, description: description, done: done, createdAt: Date(), completedAt: Date())
}

/// Replays a fixed set of SSE frames and then holds the stream open, the way a live daemon does
/// between state changes. Records what the client sends so tests can assert on it.
final class StubTransport: DaemonTransport, @unchecked Sendable {
    struct Request: Equatable {
        let method: String
        let path: String
        let body: String
    }

    private let frames: [Data]
    private let taskList: Data
    private let lock = NSLock()
    private var recorded: [Request] = []

    var requests: [Request] { lock.withLock { recorded } }

    /// Everything but the task-list refresh the client runs after each frame.
    var commands: [Request] { requests.filter { $0.path != Self.tasksPath } }

    init(states: [DaemonState], tasks: TaskList = TaskList()) throws {
        frames = try states.map { try daemonEncoder.encode($0) }
        taskList = try daemonEncoder.encode(tasks)
    }

    func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
        let request = Request(
            method: method, path: path, body: body.map { String(decoding: $0, as: UTF8.self) } ?? "")
        lock.withLock { recorded.append(request) }
        return HTTPResponse(status: 200, headers: [:], body: path == Self.tasksPath ? taskList : Self.commandReply)
    }

    func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames {
                continuation.yield(frame)
            }
        }
    }

    private static let tasksPath = "/v1/tasks"
    private static let commandReply = Data(#"{"message":"ok"}"#.utf8)
}

/// A transport that refuses the event stream, the way it does when the daemon is not running.
final class UnreachableDaemonTransport: DaemonTransport, @unchecked Sendable {
    private let message: String

    init(message: String = "no daemon") {
        self.message = message
    }

    func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
        throw DaemonError.transport(message)
    }

    func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish(throwing: DaemonError.transport(self.message)) }
    }
}

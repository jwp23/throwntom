import Foundation
import XCTest
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

/// A daemon snapshot without timestamps, so `DaemonJSON.encoder` output round-trips through
/// the Go-time decoder the client uses.
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

/// Replays a fixed set of SSE frames and then holds the stream open, the way a live daemon
/// does between state changes.
final class StubTransport: DaemonTransport, @unchecked Sendable {
    private let frames: [Data]
    private let emptyTaskList = Data(#"{"active":[],"completed":[]}"#.utf8)

    init(states: [DaemonState]) throws {
        frames = try states.map { try DaemonJSON.encoder.encode($0) }
    }

    func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
        HTTPResponse(status: 200, headers: [:], body: emptyTaskList)
    }

    func events(_ path: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for frame in frames {
                continuation.yield(frame)
            }
        }
    }
}

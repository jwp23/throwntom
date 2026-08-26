import Foundation
import Observation

/// Owns the event stream and publishes the daemon's DaemonState and task list to the views.
@Observable @MainActor
public final class DaemonClient {
    public enum Connection: Equatable, Sendable {
        case connecting
        case connected
        case reconnecting(attempt: Int)
        /// Consecutive failures reached the threshold; the launchd agent has been asked to start the daemon.
        case startingDaemon
    }

    nonisolated public static let failuresBeforeRegistering = 3
    nonisolated public static let defaultBackoff: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(8)]

    public private(set) var state: DaemonState?
    public private(set) var tasks = TaskList()
    public private(set) var connection = Connection.connecting
    public private(set) var lastError: String?

    private let transport: DaemonTransport
    private let registrar: LaunchAgentRegistrar
    private let backoff: [Duration]
    private var streamTask: Task<Void, Never>?

    public init(transport: DaemonTransport, registrar: LaunchAgentRegistrar, backoff: [Duration] = DaemonClient.defaultBackoff) {
        precondition(!backoff.isEmpty, "backoff needs at least one delay")
        self.transport = transport
        self.registrar = registrar
        self.backoff = backoff
    }

    public func start() {
        guard streamTask == nil else { return }
        streamTask = Task { await runStream() }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: Commands

    public func command(_ line: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["line": line])
        let response = try await post(DaemonAPI.command, body: body)
        return try DaemonJSON.decoder.decode(CommandReply.self, from: response.body).message
    }

    public func timer(_ verb: TimerVerb) async throws {
        _ = try await post(DaemonAPI.timer(verb), body: nil)
    }

    public func snooze(minutes: Int) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["minutes": minutes])
        _ = try await post(DaemonAPI.snooze, body: body)
    }

    public func refreshTasks() async {
        do {
            let response = try await transport.request("GET", DaemonAPI.tasks, body: nil)
            try Self.check(response)
            tasks = try DaemonJSON.decoder.decode(TaskList.self, from: response.body)
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: Stream

    private func runStream() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                for try await frame in transport.events(DaemonAPI.events) {
                    let decoded = try DaemonJSON.decoder.decode(DaemonState.self, from: frame)
                    failures = 0
                    connection = .connected
                    state = decoded
                    await refreshTasks()
                }
                throw DaemonError.transport("event stream ended")
            } catch {
                if Task.isCancelled { return }
                failures += 1
                lastError = String(describing: error)
                if failures > 0 && failures % Self.failuresBeforeRegistering == 0 {
                    registerAgent()
                }
                connection = failures >= Self.failuresBeforeRegistering ? .startingDaemon : .reconnecting(attempt: failures)
                let delay = backoff[min(failures - 1, backoff.count - 1)]
                try? await Task.sleep(for: delay)
            }
        }
    }

    private func registerAgent() {
        do {
            try registrar.ensureAgentRegistered()
        } catch {
            lastError = "register agent: \(error)"
        }
    }

    // MARK: HTTP helpers

    private func post(_ path: String, body: Data?) async throws -> HTTPResponse {
        let response = try await transport.request("POST", path, body: body)
        try Self.check(response)
        return response
    }

    private static func check(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.status) else {
            throw DaemonError.http(status: response.status, message: errorMessage(response.body))
        }
    }

    private static func errorMessage(_ body: Data) -> String {
        (try? DaemonJSON.decoder.decode(ErrorReply.self, from: body))?.error
            ?? String(decoding: body, as: UTF8.self)
    }
}

/// Fixed daemon HTTP API paths, named in one place instead of scattered string literals.
private enum DaemonAPI {
    static let command = "/v1/command"
    static let tasks = "/v1/tasks"
    static let events = "/v1/events"
    static let snooze = "/v1/timer/snooze"

    static func timer(_ verb: TimerVerb) -> String { "/v1/timer/\(verb.rawValue)" }
}

private struct CommandReply: Decodable {
    let message: String
}

private struct ErrorReply: Decodable {
    let error: String
}

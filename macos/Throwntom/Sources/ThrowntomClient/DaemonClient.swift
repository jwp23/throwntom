import Foundation
import Observation

// MARK: - DaemonClient

/// Owns the event stream and publishes the daemon's DaemonState and task list to the views.
@Observable @MainActor
public final class DaemonClient {

  // MARK: Lifecycle

  public init(transport: DaemonTransport, registrar: LaunchAgentRegistrar, backoff: [Duration] = DaemonClient.defaultBackoff) {
    precondition(!backoff.isEmpty, "backoff needs at least one delay")
    self.transport = transport
    self.registrar = registrar
    self.backoff = backoff
  }

  // MARK: Public

  public enum Connection: Equatable, Sendable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    /// Consecutive failures reached the threshold; the launchd agent has been asked to start the daemon.
    case startingDaemon
  }

  nonisolated public static let failuresBeforeRegistering = 3
  nonisolated public static let defaultBackoff: [Duration] = [
    .milliseconds(500),
    .seconds(1),
    .seconds(2),
    .seconds(4),
    .seconds(8),
  ]

  public private(set) var state: DaemonState?
  public private(set) var tasks = TaskList()
  public private(set) var connection = Connection.connecting
  public private(set) var lastError: String?

  /// Set when a user-triggered command is refused, cleared by the next one that succeeds.
  /// Tracked apart from `lastError` because a refusal happens while still connected, so it
  /// must not be hidden by the connection guard below.
  public private(set) var commandError: String?

  /// The last error while it still matters: reconnecting hides `lastError` without forgetting
  /// it, but a refused command is shown regardless of connection state.
  public var unresolvedError: String? {
    if let commandError {
      commandError
    } else if connection == .connected {
      nil
    } else {
      lastError
    }
  }

  public func start() {
    guard streamTask == nil else { return }
    streamTask = Task { await runStream() }
  }

  public func stop() {
    streamTask?.cancel()
    streamTask = nil
  }

  public func command(_ line: String) async throws -> String {
    try await runCommand {
      let body = try JSONSerialization.data(withJSONObject: ["line": line])
      let response = try await post(DaemonAPI.command, body: body)
      return try DaemonJSON.decoder.decode(CommandReply.self, from: response.body).message
    }
  }

  public func timer(_ verb: TimerVerb) async throws {
    try await runCommand {
      _ = try await post(DaemonAPI.timer(verb), body: nil)
    }
  }

  /// Runs a timer action: every action but snooze is a verb path with no body.
  public func perform(_ action: TimerAction) async throws {
    if let verb = action.verb {
      try await timer(verb)
    } else {
      try await snooze(minutes: TimerActions.defaultSnoozeMinutes)
    }
  }

  public func snooze(minutes: Int) async throws {
    try await runCommand {
      let body = try JSONSerialization.data(withJSONObject: ["minutes": minutes])
      _ = try await post(DaemonAPI.snooze, body: body)
    }
  }

  public func refreshTasks() async {
    do {
      let response = try await transport.request("GET", DaemonAPI.tasks, body: nil)
      try Self.check(response)
      tasks = try DaemonJSON.decoder.decode(TaskList.self, from: response.body)
    } catch {
      lastError = Self.userMessage(error)
    }
  }

  public func stats() async throws -> StatsSummary {
    let response = try await transport.request("GET", DaemonAPI.stats, body: nil)
    try Self.check(response)
    return try DaemonJSON.decoder.decode(StatsSummary.self, from: response.body)
  }

  // MARK: Private

  private let transport: DaemonTransport
  private let registrar: LaunchAgentRegistrar
  private let backoff: [Duration]
  private var streamTask: Task<Void, Never>?

  private static func check(_ response: HTTPResponse) throws {
    guard (200..<300).contains(response.status) else {
      throw DaemonError.http(status: response.status, message: errorMessage(response.body))
    }
  }

  private static func errorMessage(_ body: Data) -> String {
    (try? DaemonJSON.decoder.decode(ErrorReply.self, from: body))?.error
      ?? String(decoding: body, as: UTF8.self)
  }

  /// The window's wording for anything that goes wrong, so no view has to render a raw error.
  /// Anything that is not a `DaemonError` got as far as a reply the client could not decode,
  /// so it is reported as an unreadable answer rather than as an unreachable daemon.
  private static func userMessage(_ error: Error) -> String {
    (error as? DaemonError)?.userMessage ?? DaemonError.malformedResponse("\(error)").userMessage
  }

  private func runStream() async {
    var retries = ReconnectBackoff(delays: backoff, registerEvery: Self.failuresBeforeRegistering)
    while !Task.isCancelled {
      do {
        for try await frame in transport.events(DaemonAPI.events) {
          let decoded = try DaemonJSON.decoder.decode(DaemonState.self, from: frame)
          retries.reset()
          connection = .connected
          state = decoded
          await refreshTasks()
        }
        throw DaemonError.transport("event stream ended")
      } catch {
        if Task.isCancelled {
          return
        }
        retries.recordFailure()
        lastError = Self.userMessage(error)
        // A real outage matters more than a stale command refusal from before it started.
        commandError = nil
        // Only a registration launchd accepted justifies retrying sooner: when the ask itself
        // failed, nothing has been done about the outage and it keeps escalating.
        if retries.shouldRegisterAgent, registerAgent() {
          retries.agentRegistered()
        }
        connection = retries.failures >= Self.failuresBeforeRegistering
          ? .startingDaemon
          : .reconnecting(attempt: retries.failures)
        try? await Task.sleep(for: retries.delay)
      }
    }
  }

  /// Asks launchd to start the daemon. Returns whether the ask was accepted.
  private func registerAgent() -> Bool {
    do {
      try registrar.ensureAgentRegistered()
      return true
    } catch {
      lastError = "The timer could not be started."
      return false
    }
  }

  private func post(_ path: String, body: Data?) async throws -> HTTPResponse {
    let response = try await transport.request("POST", path, body: body)
    try Self.check(response)
    return response
  }

  /// Wraps a user-triggered command so every call site records a refusal the same way,
  /// instead of each catching it separately.
  private func runCommand<T>(_ operation: () async throws -> T) async throws -> T {
    do {
      let result = try await operation()
      commandError = nil
      return result
    } catch {
      commandError = Self.userMessage(error)
      throw error
    }
  }

}

// MARK: - DaemonAPI

/// Fixed daemon HTTP API paths, named in one place instead of scattered string literals.
private enum DaemonAPI {
  static let command = "/v1/command"
  static let tasks = "/v1/tasks"
  static let events = "/v1/events"
  static let stats = "/v1/stats"
  static let snooze = "/v1/timer/snooze"

  static func timer(_ verb: TimerVerb) -> String {
    "/v1/timer/\(verb.rawValue)"
  }
}

// MARK: - CommandReply

private struct CommandReply: Decodable {
  let message: String
}

// MARK: - ErrorReply

private struct ErrorReply: Decodable {
  let error: String
}

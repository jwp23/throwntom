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
    /// The user stopped the timer service. Nothing is dialling and nothing is wrong.
    case stopped
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

  /// Whether the daemon has ever answered — bytes arrived, whether or not they parsed. Until it
  /// has, the connection states are the whole story and the window has nothing to add to them.
  public private(set) var hasConnected = false

  /// Set when launchd refuses to start the daemon, cleared when it accepts or the daemon answers.
  /// Kept apart from `lastError` because the dial errors that follow would otherwise overwrite
  /// it within one backoff step, leaving the window on "Starting timer…" explaining nothing.
  public private(set) var registrationError: String?

  /// The last error while it still matters: reconnecting hides `lastError` without forgetting
  /// it, but a refused command is shown regardless of connection state.
  ///
  /// The reconnect note is suppressed wherever `Connection` is already saying it. "Starting
  /// timer…" and a note reading "Timer is restarting…" are two messages competing to say one
  /// thing, so the status line wins; and before the daemon has ever answered the note is untrue
  /// as well, because nothing has restarted yet. A failure to start the daemon at all is not a
  /// competing message but the reason nothing is happening, so it still reports.
  /// A live connection is checked before `registrationError` so that a stale refusal can never
  /// be shown over a running timer, whatever happens to the code that clears it.
  public var unresolvedError: String? {
    if let commandError {
      commandError
    } else if connection == .connected {
      nil
    } else if connection == .stopped {
      nil
    } else if let registrationError {
      registrationError
    } else if connection == .startingDaemon || !hasConnected {
      nil
    } else {
      lastError
    }
  }

  public func start() {
    guard streamTask == nil else { return }
    streamTask = Task { await runStream() }
  }

  /// Drops the event stream. This is what a quitting app runs, so it deliberately says nothing
  /// to launchd: the daemon outlives its clients (ADR-006).
  public func stop() {
    streamTask?.cancel()
    streamTask = nil
  }

  /// Asks launchd for the daemon and reconnects. Also the way back from a refused launch, since
  /// registering again is exactly what retries it.
  public func startService() {
    commandError = nil
    connection = .connecting
    _ = registerAgent()
    start()
  }

  /// Takes the timer service down. Nothing changes unless launchd accepts: a refused stop leaves
  /// a daemon that is still running, and claiming otherwise would leave the window lying about it.
  public func stopService() {
    do {
      try registrar.stopAgent()
    } catch {
      commandError = "The timer service could not be stopped."
      return
    }
    stop()
    state = nil
    registrationError = nil
    commandError = nil
    connection = .stopped
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
          // Before the decode: the daemon has answered even if we cannot read what it said, and
          // a daemon that is up but talking nonsense has still been reached.
          hasConnected = true
          registrationError = nil
          let decoded = try DaemonJSON.decoder.decode(DaemonState.self, from: frame)
          // Below the decode, unlike the two above it: a daemon that is up but sending frames we
          // cannot read must keep backing off. Resetting on an undecodable frame would spin the
          // reconnect loop at the shortest delay for as long as it kept babbling.
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
      registrationError = nil
      return true
    } catch {
      registrationError = "The timer could not be started."
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

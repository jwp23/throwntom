import Foundation

// MARK: - LaunchAgentRegistrar

/// Drives the launchd agent that owns throwntomd. The app never spawns the daemon itself, and
/// the daemon outlives every client (ADR-006), so the only *deliberate* stop is a user asking
/// for it through `stopAgent`. `ensureAgentRegistered` can also unregister-then-register when
/// recovery finds the agent already `.enabled` (reloading a stale entry), which briefly stops a
/// still-running daemon as a side effect — see `AgentRegistrationPlan`.
public protocol LaunchAgentRegistrar: Sendable {
  /// Makes the agent load (or reload) the daemon; called after repeated connection failures and
  /// whenever the user starts the service by hand.
  func ensureAgentRegistered() throws

  /// Unloads the agent, which is what stops the daemon. Only a user's explicit Stop calls this.
  func stopAgent() throws
}

// MARK: - LaunchAgentService

/// The launchd job the registrar acts on, in the registrar's own vocabulary. The real
/// implementation is ServiceManagement; tests substitute a fake so registration decisions can
/// be exercised without registering an agent on the machine running them.
public protocol LaunchAgentService: Sendable {
  var status: AgentStatus { get }

  func register() throws
  func unregister() throws
}

// MARK: - MainAppService

/// The app's own login item, in the registrar's own vocabulary. The real implementation is
/// ServiceManagement; tests substitute a fake so login item decisions can be exercised without
/// touching the machine's Login Items.
public protocol MainAppService: Sendable {
  var status: AgentStatus { get }

  func register() throws
  func unregister() throws
}

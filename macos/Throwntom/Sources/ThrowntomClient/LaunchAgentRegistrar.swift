import Foundation

/// Registers the launchd agent that owns throwntomd. The app never spawns the daemon itself.
public protocol LaunchAgentRegistrar: Sendable {
    /// Makes the agent load (or reload) the daemon; called only after repeated connection failures.
    func ensureAgentRegistered() throws
}

/// The launchd job the registrar acts on, in the registrar's own vocabulary. The real
/// implementation is ServiceManagement; tests substitute a fake so registration decisions can
/// be exercised without registering an agent on the machine running them.
public protocol LaunchAgentService: Sendable {
    var status: AgentStatus { get }
    func register() throws
    func unregister() throws
}

/// The app's own login item, in the registrar's own vocabulary. The real implementation is
/// ServiceManagement; tests substitute a fake so login item decisions can be exercised without
/// touching the machine's Login Items.
public protocol MainAppService: Sendable {
    var status: AgentStatus { get }
    func register() throws
    func unregister() throws
}

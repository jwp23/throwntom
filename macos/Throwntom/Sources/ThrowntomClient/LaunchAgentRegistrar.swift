import Foundation

/// Registers the launchd agent that owns throwntomd. The app never spawns the daemon itself.
public protocol LaunchAgentRegistrar: Sendable {
    /// Idempotent: a no-op when the agent is already enabled.
    func ensureAgentRegistered() throws
}

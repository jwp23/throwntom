import Foundation

/// Registers the launchd agent that owns throwntomd. The app never spawns the daemon itself.
public protocol LaunchAgentRegistrar: Sendable {
    /// Makes the agent load (or reload) the daemon; called only after repeated connection failures.
    func ensureAgentRegistered() throws
}

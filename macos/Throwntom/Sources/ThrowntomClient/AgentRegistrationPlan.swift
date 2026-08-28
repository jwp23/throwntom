import Foundation

// MARK: - AgentStatus

/// SMAppService.Status without the framework dependency, so the plan is testable.
public enum AgentStatus: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
  case unknown
}

// MARK: - AgentRegistrationStep

public enum AgentRegistrationStep: Equatable, Sendable {
  case unregister
  case register
}

// MARK: - AgentRegistrationPlan

/// What to do with the launchd agent when the daemon is unreachable.
public enum AgentRegistrationPlan {
  /// Background Task Management can report `.enabled` while launchd no longer has the job
  /// (after `launchctl bootout` or a rebuild). Registering again is a no-op in that state;
  /// unregistering first is what makes the next register reload the job (see
  /// docs/spikes/smappservice-agent-registration/result.md).
  public static func steps(for status: AgentStatus) -> [AgentRegistrationStep] {
    switch status {
    case .enabled: [.unregister, .register]
    case .notRegistered,
         .notFound,
         .requiresApproval,
         .unknown: [.register]
    }
  }
}

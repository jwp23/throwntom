import Foundation

/// SMAppService.Status without the framework dependency, so the plan is testable.
public enum AgentStatus: Equatable, Sendable {
    case notRegistered, enabled, requiresApproval, notFound, unknown
}

public enum AgentRegistrationStep: Equatable, Sendable {
    case unregister, register
}

/// What to do with the launchd agent when the daemon is unreachable.
public enum AgentRegistrationPlan {
    /// Background Task Management can report `.enabled` while launchd no longer has the job
    /// (after `launchctl bootout` or a rebuild). Registering again is a no-op in that state;
    /// unregistering first is what makes the next register reload the job (see
    /// docs/spikes/smappservice-agent-registration/result.md).
    public static func steps(for status: AgentStatus) -> [AgentRegistrationStep] {
        switch status {
        case .enabled: return [.unregister, .register]
        case .notRegistered, .notFound, .requiresApproval, .unknown: return [.register]
        }
    }

    /// Runs the plan for `status`, handing each step to `perform`.
    /// A failed unregister is deferred rather than thrown, since a stale BTM entry may refuse
    /// to unregister while register still succeeds. The deferred error surfaces only when
    /// register fails too, because it explains why the reload never happened.
    public static func execute(
        for status: AgentStatus,
        perform: (AgentRegistrationStep) throws -> Void
    ) throws {
        var unregisterError: Error?
        for step in steps(for: status) {
            switch step {
            case .unregister:
                do { try perform(step) } catch { unregisterError = error }
            case .register:
                do { try perform(step) } catch { throw unregisterError ?? error }
            }
        }
    }

    /// Text shown beside the login item toggle, naming what the user must do next.
    public static func statusDescription(for status: AgentStatus) -> String {
        switch status {
        case .enabled: return "Timer agent enabled"
        case .requiresApproval: return "Timer agent needs approval in Login Items"
        case .notRegistered: return "Timer agent not registered"
        case .notFound: return "Timer agent plist not found in bundle"
        case .unknown: return "Timer agent status unknown"
        }
    }

    /// The login item is the same register/unregister pair driven by a plain on/off toggle.
    public static func loginItemStep(isEnabled: Bool) -> AgentRegistrationStep {
        isEnabled ? .register : .unregister
    }
}

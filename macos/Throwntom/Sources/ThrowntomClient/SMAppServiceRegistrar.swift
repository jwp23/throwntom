import Foundation
import ServiceManagement

/// Registers the bundled launchd agent and toggles the app's own login item.
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {
    public static let bundleIdentifier = "com.jwp23.throwntom"
    public static let agentPlistName = "com.jwp23.throwntom.daemon.plist"

    public init() {
        // No stored properties to initialize; this exists only so callers outside
        // the module can construct one.
    }

    private var agent: SMAppService { SMAppService.agent(plistName: Self.agentPlistName) }

    /// Ensures the launchd agent is registered, reloading if necessary.
    /// If unregister fails, we defer the error and attempt register anyway, since a stale
    /// BTM entry may refuse to unregister while register still succeeds. Only throw if both
    /// unregister and register fail, or if register fails alone.
    public func ensureAgentRegistered() throws {
        var unregisterError: Error?
        for step in AgentRegistrationPlan.steps(for: AgentStatus(agent.status)) {
            switch step {
            case .unregister:
                do { try agent.unregister() } catch { unregisterError = error }
            case .register:
                do { try agent.register() } catch { throw unregisterError ?? error }
            }
        }
    }

    public var agentStatusDescription: String {
        switch agent.status {
        case .enabled: return "Timer agent enabled"
        case .requiresApproval: return "Timer agent needs approval in Login Items"
        case .notRegistered: return "Timer agent not registered"
        case .notFound: return "Timer agent plist not found in bundle"
        @unknown default: return "Timer agent status unknown"
        }
    }

    public var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLoginItem(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension AgentStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

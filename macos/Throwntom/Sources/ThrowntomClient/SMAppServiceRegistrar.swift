import Foundation
import ServiceManagement

/// Registers the bundled launchd agent and toggles the app's own login item.
/// Every decision lives in `AgentRegistrationPlan`; what remains here is the SMAppService calls.
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {
    public static let bundleIdentifier = "com.jwp23.throwntom"
    public static let agentPlistName = "com.jwp23.throwntom.daemon.plist"

    public init() {
        // No stored properties to initialize; this exists only so callers outside
        // the module can construct one.
    }

    private var agent: SMAppService { SMAppService.agent(plistName: Self.agentPlistName) }

    /// Ensures the launchd agent is registered, reloading if necessary.
    public func ensureAgentRegistered() throws {
        let agent = self.agent
        try AgentRegistrationPlan.execute(for: AgentStatus(agent.status)) { try agent.perform($0) }
    }

    public var agentStatusDescription: String {
        AgentRegistrationPlan.statusDescription(for: AgentStatus(agent.status))
    }

    public var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLoginItem(_ enabled: Bool) throws {
        try SMAppService.mainApp.perform(AgentRegistrationPlan.loginItemStep(isEnabled: enabled))
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
        @unknown default: self = .unknown
        }
    }
}

private extension SMAppService {
    func perform(_ step: AgentRegistrationStep) throws {
        switch step {
        case .unregister: try unregister()
        case .register: try register()
        }
    }
}

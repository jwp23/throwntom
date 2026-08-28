import Foundation
import ServiceManagement

/// Registers the bundled launchd agent and toggles the app's own login item.
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {
    public static let bundleIdentifier = "com.jwp23.throwntom"
    public static let agentPlistName = "com.jwp23.throwntom.daemon.plist"

    private let agent: LaunchAgentService
    private let mainApp: MainAppService

    public init(
        agent: LaunchAgentService = BundledAgentService(),
        mainApp: MainAppService = BundledMainAppService()
    ) {
        self.agent = agent
        self.mainApp = mainApp
    }

    /// Ensures the launchd agent is registered, reloading if necessary.
    /// If unregister fails, we defer the error and attempt register anyway, since a stale
    /// BTM entry may refuse to unregister while register still succeeds. Only throw if both
    /// unregister and register fail, or if register fails alone.
    public func ensureAgentRegistered() throws {
        var unregisterError: Error?
        for step in AgentRegistrationPlan.steps(for: agent.status) {
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
        case .unknown: return "Timer agent status unknown"
        }
    }

    public var loginItemEnabled: Bool {
        mainApp.status == .enabled
    }

    public func setLoginItem(_ enabled: Bool) throws {
        if enabled {
            try mainApp.register()
        } else {
            try mainApp.unregister()
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The launchd agent shipped inside the app bundle. Every call here changes the machine's
/// registered agents, so this wrapper is deliberately thin and left to manual verification.
public struct BundledAgentService: LaunchAgentService {
    private var service: SMAppService {
        SMAppService.agent(plistName: SMAppServiceRegistrar.agentPlistName)
    }

    public init() {
        // No stored properties to initialize; this exists only so callers outside
        // the module can construct one.
    }

    public var status: AgentStatus { AgentStatus(service.status) }
    public func register() throws { try service.register() }
    public func unregister() throws { try service.unregister() }
}

/// The app's own login item. Every call here changes the machine's registered login items, so
/// this wrapper is deliberately thin and left to manual verification.
public struct BundledMainAppService: MainAppService {
    public init() {
        // No stored properties to initialize; this exists only so callers outside
        // the module can construct one.
    }

    public var status: AgentStatus { AgentStatus(SMAppService.mainApp.status) }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
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

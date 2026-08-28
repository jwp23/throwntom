import ServiceManagement

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

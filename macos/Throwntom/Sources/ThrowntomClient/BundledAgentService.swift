import ServiceManagement

/// The launchd agent shipped inside the app bundle. Every call here changes the machine's
/// registered agents, so this wrapper is deliberately thin and left to manual verification.
public struct BundledAgentService: LaunchAgentService {

  // MARK: Lifecycle

  public init() {
    // No stored properties to initialize; this exists only so callers outside
    // the module can construct one.
  }

  // MARK: Public

  public var status: AgentStatus {
    AgentStatus(service.status)
  }

  public func register() throws {
    try service.register()
  }

  public func unregister() throws {
    try service.unregister()
  }

  // MARK: Private

  private var service: SMAppService {
    SMAppService.agent(plistName: SMAppServiceRegistrar.agentPlistName)
  }

}

import ServiceManagement

/// The app's own login item. Every call here changes the machine's registered login items, so
/// this wrapper is deliberately thin and left to manual verification.
public struct BundledMainAppService: MainAppService {
  public init() {
    // No stored properties to initialize; this exists only so callers outside
    // the module can construct one.
  }

  public var status: AgentStatus {
    AgentStatus(SMAppService.mainApp.status)
  }

  public func register() throws {
    try SMAppService.mainApp.register()
  }

  public func unregister() throws {
    try SMAppService.mainApp.unregister()
  }
}

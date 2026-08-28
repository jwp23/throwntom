import Foundation
import ServiceManagement

// MARK: - SMAppServiceRegistrar

/// Registers the bundled launchd agent and toggles the app's own login item.
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {

  // MARK: Lifecycle

  public init(
    agent: LaunchAgentService = BundledAgentService(),
    mainApp: MainAppService = BundledMainAppService(),
  ) {
    self.agent = agent
    self.mainApp = mainApp
  }

  // MARK: Public

  public static let bundleIdentifier = "com.jwp23.throwntom"
  public static let agentPlistName = "com.jwp23.throwntom.daemon.plist"

  public var agentStatusDescription: String {
    switch agent.status {
    case .enabled: "Timer agent enabled"
    case .requiresApproval: "Timer agent needs approval in Login Items"
    case .notRegistered: "Timer agent not registered"
    case .notFound: "Timer agent plist not found in bundle"
    case .unknown: "Timer agent status unknown"
    }
  }

  public var loginItemEnabled: Bool {
    mainApp.status == .enabled
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

  // MARK: Private

  private let agent: LaunchAgentService
  private let mainApp: MainAppService

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

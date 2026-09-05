import Foundation
import ServiceManagement

// MARK: - SMAppServiceRegistrar

/// Registers the launchd agent that owns the daemon and toggles the app's own login item.
///
/// The two halves use different mechanisms on purpose. The login item is the app itself, which
/// SMAppService handles well. The agent is a plain LaunchAgent naming an absolute path, because
/// an SMAppService agent is pinned to the designated requirement of the signature it was
/// registered with, and an ad-hoc build's requirement changes with the code (ADR-012).
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {

  // MARK: Lifecycle

  public init(
    agent: LaunchAgentService = LaunchdAgentService(),
    mainApp: MainAppService = BundledMainAppService(),
  ) {
    self.agent = agent
    self.mainApp = mainApp
  }

  // MARK: Public

  public static let bundleIdentifier = "com.jwp23.throwntom"

  public var agentStatusDescription: String {
    switch agent.status {
    case .enabled: "Timer agent enabled"
    case .requiresApproval: "Timer agent needs approval in Login Items"
    case .notRegistered: "Timer agent not registered"
    case .notFound: "Timer daemon missing from the app bundle"
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
        do { try agent.unregister() } catch {
          // Kept for the register below to throw if that fails too, and recorded here because
          // when register succeeds it is thrown away: a stale entry that refuses to unregister
          // is the thing to know about, and registering over it stops working eventually.
          ClientLog.failed("unregister the stale launch agent", in: .service, error: error)
          unregisterError = error
        }

      case .register:
        do { try agent.register() } catch { throw unregisterError ?? error }
      }
    }
  }

  /// Unregisters the agent, the ServiceManagement equivalent of `launchctl bootout`: launchd
  /// unloads the job and the daemon exits. It stays down until something registers it again.
  public func stopAgent() throws {
    try agent.unregister()
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

import Foundation
import ServiceManagement

/// Registers the bundled launchd agent and toggles the app's own login item.
public struct SMAppServiceRegistrar: LaunchAgentRegistrar {
    public static let bundleIdentifier = "com.jwp23.throwntom"
    public static let agentPlistName = "com.jwp23.throwntom.daemon.plist"

    public init() {}

    private var agent: SMAppService { SMAppService.agent(plistName: Self.agentPlistName) }

    public func ensureAgentRegistered() throws {
        guard agent.status != .enabled else { return }
        try agent.register()
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

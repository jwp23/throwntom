import Foundation
import ThrowntomClient

// MARK: - LoginItemRegistrar

/// The login-item half of the registrar, so the toggle's behaviour can be worked out without
/// touching the user's real Login Items.
protocol LoginItemRegistrar {
  var loginItemEnabled: Bool { get }

  func setLoginItem(_ enabled: Bool) throws
}

// MARK: - SMAppServiceRegistrar + LoginItemRegistrar

extension SMAppServiceRegistrar: LoginItemRegistrar { }

// MARK: - LoginItemSetting

/// Where the "Launch at login" toggle sits, and what is written under it, once macOS has been
/// asked to move it. macOS refuses while the login item is managed or its approval was revoked,
/// and then the toggle belongs where macOS says it is, not where the user dragged it.
struct LoginItemSetting: Equatable {
  var isOn: Bool
  /// nil while nothing has gone wrong, which leaves the agent's own status showing instead.
  var message: String?

  /// `current` is what the toggle already shows. A failed change snaps `isOn` back to
  /// `registrar.loginItemEnabled`, which re-fires the toggle's `onChange` with that same value;
  /// without this guard the bounce would ask the registrar to do nothing and, on success, wipe
  /// the failure message the first call just set.
  static func afterSetting(_ enabled: Bool, in registrar: LoginItemRegistrar, current: LoginItemSetting) -> LoginItemSetting {
    guard enabled != registrar.loginItemEnabled else {
      return current
    }
    do {
      try registrar.setLoginItem(enabled)
      return LoginItemSetting(isOn: enabled, message: nil)
    } catch {
      return LoginItemSetting(
        isOn: registrar.loginItemEnabled,
        message: "Login item: \(error.localizedDescription)",
      )
    }
  }
}

import SwiftUI
import ThrowntomClient

/// The "Launch at Login" item in the application menu, plus the reason when macOS refuses.
struct LoginItemToggle: View {

  // MARK: Internal

  let registrar: LoginItemRegistrar

  var body: some View {
    Toggle("Launch at Login", isOn: $setting.isOn)
      .onChange(of: setting.isOn) { _, enabled in setting = .afterSetting(enabled, in: registrar, current: setting) }
      .onAppear { setting.isOn = registrar.loginItemEnabled }
    if let message = setting.message {
      Text(message)
    }
  }

  // MARK: Private

  @State private var setting = LoginItemSetting(isOn: false, message: nil)

}

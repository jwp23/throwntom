import SwiftUI

/// The app's entry point. The executable target does nothing but call `main()` on this, so
/// everything it wires together lives in a library the tests can import.
public struct ThrowntomApp: App {
  /// The daemon connection and the clock start here, not in a view's onAppear: the popover
  /// content only appears when opened.
  public init() {
    let environment = AppEnvironment.live()
    environment.startReminderResponder()
    environment.start()
    _environment = State(initialValue: environment)
  }

  public var body: some Scene {
    ThrowntomScenes(environment: environment)
  }

  @State private var environment: AppEnvironment
}

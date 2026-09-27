import SwiftUI

/// The app's entry point. The executable target does nothing but call `main()` on this, so
/// everything it wires together lives in a library the tests can import.
public struct ThrowntomApp: App {

  // MARK: Lifecycle

  /// What the executable launches: the app around the one environment that talks to the real
  /// daemon, the real notification centre and the user's own defaults.
  public init() {
    self.init(environment: .live())
  }

  /// The daemon connection and the clock start here, not in a view's onAppear: the window's
  /// content only appears once SwiftUI has rendered it.
  ///
  /// The environment is handed in so that a test can launch the app around stand-ins. Only this
  /// package can: `AppEnvironment` is internal, and the executable has the initialiser above.
  init(environment: AppEnvironment) {
    environment.startReminderResponder()
    environment.start()
    _environment = State(initialValue: environment)
  }

  // MARK: Public

  public var body: some Scene {
    ThrowntomScenes(environment: environment)
  }

  // MARK: Private

  @State private var environment: AppEnvironment

}

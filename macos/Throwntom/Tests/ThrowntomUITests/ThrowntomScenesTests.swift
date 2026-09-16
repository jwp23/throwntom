import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - ThrowntomScenesTests

/// What the one scene is actually made of, read back out of `ThrowntomScenes.body`. `Scene` is a
/// third SwiftUI builder protocol beside `View` and `Commands`, and it erases just as little: each
/// statement a `SceneBuilder` block contributes, and each generic parameter a nested builder
/// closure fixes, becomes part of `body`'s own type — so `MainWindow` disappearing from the
/// window's content, or `AppMenus` from its commands, or the whole scene collapsing to nothing,
/// all show up in one exact type string.
@MainActor
final class ThrowntomScenesTests: XCTestCase {
  func testTheSceneIsTheMainWindowStyledAndCarryingTheAppMenus() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))

    let scene = ThrowntomScenes(environment: environment).body

    XCTAssertEqual(
      shape(of: scene),
      "ModifiedContent<ModifiedContent<ModifiedContent<Window<MainWindow>, "
        + "WindowStyleModifier<HiddenTitleBarWindowStyle>>, TransformSceneListModifier>, "
        + "CommandsModifier<AppMenus>>",
    )
  }
}

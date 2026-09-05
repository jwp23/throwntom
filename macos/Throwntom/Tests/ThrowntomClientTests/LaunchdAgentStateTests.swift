import XCTest

@testable import ThrowntomClient

final class LaunchdAgentStateTests: XCTestCase {

  // MARK: Internal

  func testAnAgentRunningThisBundlesDaemonIsEnabled() {
    XCTAssertEqual(
      LaunchdAgentState.status(installedProgramPath: daemon, expectedProgramPath: daemon, isLoaded: true),
      .enabled,
    )
  }

  func testAnAgentThatIsNotInstalledIsNotRegistered() {
    XCTAssertEqual(
      LaunchdAgentState.status(installedProgramPath: nil, expectedProgramPath: daemon, isLoaded: false),
      .notRegistered,
    )
  }

  /// An upgrade replaces the bundle in place. launchd keeps running whatever the plist named, so
  /// a plist naming the previous copy has to read as "needs registering" or the app would sit
  /// waiting on a daemon that belongs to a bundle it just replaced.
  func testAnAgentPointingAtAnotherBundleIsNotRegistered() {
    XCTAssertEqual(
      LaunchdAgentState.status(
        installedProgramPath: "/Users/x/old/Throwntom.app/Contents/MacOS/throwntomd",
        expectedProgramPath: daemon,
        isLoaded: true,
      ),
      .notRegistered,
    )
  }

  /// The plist survives a bootout, so its presence alone says nothing about whether launchd is
  /// running the job.
  func testACorrectPlistThatLaunchdHasNotLoadedIsNotRegistered() {
    XCTAssertEqual(
      LaunchdAgentState.status(installedProgramPath: daemon, expectedProgramPath: daemon, isLoaded: false),
      .notRegistered,
    )
  }

  // MARK: Private

  private let daemon = "/Users/x/Applications/Throwntom.app/Contents/MacOS/throwntomd"

}

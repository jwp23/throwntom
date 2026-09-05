import Foundation

// MARK: - LaunchdAgentState

/// Whether launchd is running the daemon this bundle ships, decided from what can be observed:
/// the plist on disk and whether the job is loaded. Kept apart from the process calls below so
/// the rule can be tested without registering an agent on the machine running the tests.
public enum LaunchdAgentState {
  public static func status(
    installedProgramPath: String?,
    expectedProgramPath: String,
    isLoaded: Bool,
  ) -> AgentStatus {
    guard installedProgramPath == expectedProgramPath, isLoaded else {
      return .notRegistered
    }
    return .enabled
  }
}

// MARK: - LaunchdAgentError

public enum LaunchdAgentError: Error {
  /// launchctl refused the job. The status is its exit code; its output is deliberately not
  /// carried, so nothing the user typed or named can reach a log through an error message.
  case launchctlFailed(command: String, status: Int32)
  case daemonMissingFromBundle
}

// MARK: - LaunchdAgentService

/// The launchd agent that owns throwntomd, driven as a plain LaunchAgent naming an absolute
/// path (ADR-012). Every call here changes the machine's launchd state, so this wrapper is
/// deliberately thin; `tools/agent-reinstall-check.sh` is what exercises it end to end.
public struct LaunchdAgentService: LaunchAgentService {

  // MARK: Lifecycle

  /// Takes the bundle's URL rather than the `Bundle`: this type is `Sendable`, and `Bundle` is a
  /// reference type that is not. The URL is all the agent needs, and a test can point it at one
  /// it made itself.
  ///
  /// `launchctl` is injected for the same reason: what matters here is the order the job is torn
  /// down and loaded in, and a test can only watch that if it can stand in for the process.
  public init(
    bundleURL: URL = Bundle.main.bundleURL,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    launchctl: @escaping Launchctl = LaunchdAgentService.runLaunchctl,
  ) {
    self.bundleURL = bundleURL
    self.home = home
    self.launchctl = launchctl
  }

  // MARK: Public

  /// Runs launchctl with the given arguments and returns its exit status.
  public typealias Launchctl = @Sendable ([String]) -> Int32

  public var status: AgentStatus {
    guard let daemonPath = try? daemonPath() else {
      return .notFound
    }
    return LaunchdAgentState.status(
      installedProgramPath: LaunchdAgentPlist.programPath(inPlistAt: plistURL),
      expectedProgramPath: daemonPath,
      isLoaded: isLoaded,
    )
  }

  /// The real process call, used unless a test substitutes for it.
  public static func runLaunchctl(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return -1
    }
    process.waitUntilExit()
    return process.terminationStatus
  }

  /// Writes the plist for this bundle's daemon and loads it. The bootout first makes this safe
  /// to call over an agent that is already loaded — including one left pointing at the bundle an
  /// upgrade replaced, which is the case that has to end with launchd running the new daemon.
  public func register() throws {
    let plist = LaunchdAgentPlist(programPath: try daemonPath())
    try FileManager.default.createDirectory(
      at: plistURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try plist.data().write(to: plistURL)
    _ = launchctl(["bootout", serviceTarget])
    try run(["bootstrap", domainTarget, plistURL.path])
  }

  /// Unloads the agent and removes its plist, so nothing reloads the daemon at the next login.
  public func unregister() throws {
    _ = launchctl(["bootout", serviceTarget])
    try? FileManager.default.removeItem(at: plistURL)
  }

  // MARK: Private

  private let bundleURL: URL
  private let home: URL
  private let launchctl: Launchctl

  private var plistURL: URL {
    LaunchdAgentPlist.url(inHome: home)
  }

  private var domainTarget: String {
    "gui/\(getuid())"
  }

  private var serviceTarget: String {
    "\(domainTarget)/\(LaunchdAgentPlist.label)"
  }

  private var isLoaded: Bool {
    launchctl(["print", serviceTarget]) == 0
  }

  private func daemonPath() throws -> String {
    let path = bundleURL.appendingPathComponent("Contents/MacOS/throwntomd").path
    guard FileManager.default.isExecutableFile(atPath: path) else {
      throw LaunchdAgentError.daemonMissingFromBundle
    }
    return path
  }

  private func run(_ arguments: [String]) throws {
    let status = launchctl(arguments)
    guard status == 0 else {
      throw LaunchdAgentError.launchctlFailed(command: arguments.first ?? "", status: status)
    }
  }

}

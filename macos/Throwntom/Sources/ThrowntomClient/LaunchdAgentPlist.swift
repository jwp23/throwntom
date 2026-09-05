import Foundation

// MARK: - LaunchdAgentPlist

/// The launchd job description for throwntomd, as a value.
///
/// The daemon runs from a plain LaunchAgent naming an absolute path, not from the bundled agent
/// SMAppService registers. Background Task Management pins a registered agent to the designated
/// requirement of the signature it was registered with, and an ad-hoc signature's requirement is
/// its cdhash — which changes with the code. A rebuilt daemon therefore failed the launch
/// constraint on its next spawn and KeepAlive looped on a record launchd could no longer resolve.
/// An absolute path has no such requirement to go stale, so an upgrade starts (ADR-012).
public struct LaunchdAgentPlist: Equatable, Sendable {

  // MARK: Lifecycle

  public init(programPath: String) {
    self.programPath = programPath
  }

  // MARK: Public

  public static let label = "com.jwp23.throwntom.daemon"

  public let programPath: String

  /// Where launchd looks for this agent. Everything in the directory is loaded at login, which
  /// is what starts the daemon for a new session.
  public static func url(inHome home: URL) -> URL {
    home
      .appendingPathComponent("Library/LaunchAgents")
      .appendingPathComponent("\(label).plist")
  }

  /// The daemon an already-installed plist points at, or nil when there is no readable plist.
  /// A path that is not this bundle's is how an upgraded app notices launchd is still running
  /// the copy it replaced.
  public static func programPath(inPlistAt url: URL) -> String? {
    guard
      let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let arguments = (plist as? [String: Any])?["ProgramArguments"] as? [String]
    else {
      return nil
    }
    return arguments.first
  }

  public func data() throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: [
        "Label": Self.label,
        "ProgramArguments": [programPath],
        "RunAtLoad": true,
        // Revive the daemon when it fails, never when it stops on purpose: a second throwntomd
        // that loses the single-instance lock exits 0 and stands down, and restarting it would
        // put it straight back into the race it just lost.
        "KeepAlive": ["SuccessfulExit": false],
      ],
      format: .xml,
      options: 0,
    )
  }

}

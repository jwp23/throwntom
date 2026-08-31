import AppKit
import ThrowntomClient

/// The TOML the daemon reads, opened in whatever the user edits text with.
enum ConfigFile {
  /// `open` answers whether anything took the file, and nothing else reports: a menu item that
  /// quietly does nothing looks identical to one that worked. The opener is injectable so that
  /// refusal can be exercised without a real editor coming up.
  static func open(with opener: (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
    guard !opener(DaemonPaths.configFileToOpen()) else { return }
    // The path is not passed on. It is the same fixed location every time, so it says nothing a
    // reader does not already know, and the log carries state and never file contents or names.
    ClientLog.refused("open the config file", in: .service, reason: "no application accepted it")
  }
}

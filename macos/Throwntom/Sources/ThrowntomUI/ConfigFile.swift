import AppKit
import ThrowntomClient

/// The TOML the daemon reads, opened in whatever the user edits text with.
enum ConfigFile {
  static func open() {
    NSWorkspace.shared.open(DaemonPaths.configFileToOpen())
  }
}

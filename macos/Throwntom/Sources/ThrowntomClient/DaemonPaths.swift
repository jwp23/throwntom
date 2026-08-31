import Foundation

public enum DaemonPaths {
  /// Mirrors core.DefaultPaths().Socket on the Go side.
  public static var socketPath: String {
    configDirectory().appending(path: "daemon.sock").path
  }

  /// Where the daemon keeps its config and state. Mirrors config.DirPath on the Go side.
  public static func configDirectory(inHome home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    home.appending(path: ".config/throwntom")
  }

  /// What "Open Config File…" reveals: the config file itself, or its directory when there is no file yet.
  public static func configFileToOpen(inHome home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
    let directory = configDirectory(inHome: home)
    let file = directory.appending(path: "config.toml")
    return if FileManager.default.fileExists(atPath: file.path) {
      file
    } else {
      directory
    }
  }
}

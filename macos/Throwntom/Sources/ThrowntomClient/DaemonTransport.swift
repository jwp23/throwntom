import Foundation

// MARK: - HTTPResponse

public struct HTTPResponse: Equatable, Sendable {
  public init(status: Int, headers: [String: String], body: Data) {
    self.status = status
    self.headers = headers
    self.body = body
  }

  public var status: Int
  public var headers: [String: String]
  public var body: Data
}

// MARK: - DaemonError

public enum DaemonError: Error, Equatable {
  case transport(String)
  case malformedResponse(String)
  case http(status: Int, message: String)
  /// The daemon accepted the connection but did not complete the response in time.
  case timedOut(after: Duration)
}

extension DaemonError {
  /// What the window says about this error. The daemon's own words for a refusal, since it
  /// explains itself in plain language; a sentence of our own for everything else, because the
  /// alternative is showing the reader a socket error verbatim.
  public var userMessage: String {
    switch self {
    case .transport: "Timer is restarting…"
    case .malformedResponse: "The timer sent a reply we could not read."
    case .http(_, let message): message
    case .timedOut: "The timer is not responding."
    }
  }
}

// MARK: - DaemonTransport

/// How the client reaches throwntomd. One implementation today (Unix socket); a TCP one can be added behind this.
public protocol DaemonTransport: Sendable {
  func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse
  /// Yields the data payload of each SSE frame; finishes with an error when the stream drops.
  func events(_ path: String) -> AsyncThrowingStream<Data, Error>
}

// MARK: - DaemonPaths

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

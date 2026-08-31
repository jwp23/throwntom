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

public enum DaemonError: Error, Equatable, Sendable {
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

  /// The window's wording for anything that goes wrong, so no view has to render a raw error.
  /// Anything that is not a `DaemonError` got as far as a reply the client could not decode, so it
  /// is reported as an unreadable answer rather than as an unreachable daemon; its own description
  /// is dropped, because a Swift error's text is not something a reader can act on.
  ///
  /// Public so every surface that catches a failure — the client's own commands and the panels
  /// that call it directly — words it the same way.
  public static func userMessage(for error: Error) -> String {
    // The empty payload is not an oversight: `malformedResponse`'s `userMessage` is a fixed
    // sentence and never reads its associated value, so describing the error here would build a
    // string only to drop it — and read as though the detail survived into the window.
    (error as? DaemonError)?.userMessage ?? DaemonError.malformedResponse("").userMessage
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

import Foundation

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public enum DaemonError: Error, Equatable {
    case transport(String)
    case malformedResponse(String)
    case http(status: Int, message: String)
    /// The daemon accepted the connection but did not complete the response in time.
    case timedOut(after: Duration)
}

/// How the client reaches throwntomd. One implementation today (Unix socket); a TCP one can be added behind this.
public protocol DaemonTransport: Sendable {
    func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse
    /// Yields the data payload of each SSE frame; finishes with an error when the stream drops.
    func events(_ path: String) -> AsyncThrowingStream<Data, Error>
}

public enum DaemonPaths {
    /// Mirrors core.DefaultPaths().Socket on the Go side.
    public static var socketPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/throwntom/daemon.sock").path
    }
}

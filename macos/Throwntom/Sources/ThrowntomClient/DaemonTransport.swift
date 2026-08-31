import Foundation

/// How the client reaches throwntomd. One implementation today (Unix socket); a TCP one can be added behind this.
public protocol DaemonTransport: Sendable {
  func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse
  /// Yields the data payload of each SSE frame; finishes with an error when the stream drops.
  func events(_ path: String) -> AsyncThrowingStream<Data, Error>
}

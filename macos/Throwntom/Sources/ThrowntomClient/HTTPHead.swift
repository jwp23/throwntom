public struct HTTPHead: Equatable, Sendable {
  public var status: Int
  /// Header names lowercased; duplicate names keep the last value.
  public var headers: [String: String]

  public var isChunked: Bool {
    headers["transfer-encoding"]?.lowercased().contains("chunked") ?? false
  }

  public var contentLength: Int? {
    headers["content-length"].flatMap(Int.init)
  }
}

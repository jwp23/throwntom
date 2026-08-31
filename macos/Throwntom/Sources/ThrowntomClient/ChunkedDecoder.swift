import Foundation

/// Incremental decoder for Transfer-Encoding: chunked bodies.
public struct ChunkedDecoder {

  // MARK: Lifecycle

  public init() {
    // No initialization needed: every stored property has a declared default
    // (phase .size, empty buffer).
  }

  // MARK: Public

  public static let maxChunkBytes = 1_048_576

  public private(set) var isFinished = false

  /// Feeds raw bytes and returns whatever decoded body bytes became available.
  public mutating func feed(_ data: Data) throws -> Data {
    buffer += data
    var out = Data()
    while true {
      switch phase {
      case .size:
        guard let range = buffer.range(of: Self.crlf) else {
          if buffer.count > Self.maxSizeLineBytes {
            throw HTTPParseError.malformedChunkSize(String(decoding: buffer, as: UTF8.self))
          }
          return out
        }
        let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        let sizeText = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
          throw HTTPParseError.malformedChunkSize(line)
        }
        guard size >= 0, size <= Self.maxChunkBytes else {
          throw HTTPParseError.malformedChunkSize(line)
        }
        buffer = Data(buffer[range.upperBound...])
        phase = size == 0 ? .finished : .body(remaining: size)

      case .body(let remaining):
        if buffer.isEmpty {
          return out
        }
        let take = min(remaining, buffer.count)
        out += buffer.prefix(take)
        buffer = Data(buffer.dropFirst(take))
        phase = remaining == take ? .bodyTerminator : .body(remaining: remaining - take)

      case .bodyTerminator:
        guard buffer.count >= 2 else { return out }
        guard buffer.prefix(2) == Self.crlf else { throw HTTPParseError.malformedChunkTerminator }
        buffer = Data(buffer.dropFirst(2))
        phase = .size

      case .finished:
        isFinished = true
        return out
      }
    }
  }

  // MARK: Private

  private enum Phase { case size, body(remaining: Int), bodyTerminator, finished }

  private static let crlf = Data("\r\n".utf8)
  private static let maxSizeLineBytes = 64

  private var phase = Phase.size
  private var buffer = Data()

}

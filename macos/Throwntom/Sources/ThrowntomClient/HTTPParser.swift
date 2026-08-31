import Foundation

/// Minimal HTTP/1.1 response parsing for a single trusted peer (Go net/http).
public enum HTTPParser {

  // MARK: Public

  public static let maxHeadBytes = 65_536

  /// Parses the status line and headers. Returns nil when the terminator has not arrived yet.
  public static func parseHead(_ data: Data) throws -> (head: HTTPHead, bodyStart: Int)? {
    guard let range = data.range(of: headTerminator) else {
      if data.count > maxHeadBytes {
        throw HTTPParseError.headTooLarge
      }
      return nil
    }
    if range.lowerBound - data.startIndex > maxHeadBytes {
      throw HTTPParseError.headTooLarge
    }
    let headText = String(decoding: data[data.startIndex..<range.lowerBound], as: UTF8.self)
    var lines = headText.components(separatedBy: "\r\n")
    let statusLine = lines.removeFirst()
    let parts = statusLine.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."), let status = Int(parts[1]) else {
      throw HTTPParseError.malformedStatusLine(statusLine)
    }
    var headers = [String: String]()
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[..<colon].lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }
    return (HTTPHead(status: status, headers: headers), range.upperBound - data.startIndex)
  }

  // MARK: Private

  private static let headTerminator = Data("\r\n\r\n".utf8)

}

import Foundation
import Synchronization

/// JSON conventions of the throwntomd API: snake_case keys and Go RFC3339Nano timestamps.
public enum DaemonJSON {

  // MARK: Public

  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
      let raw = try decoder.singleValueContainer().decode(String.self)
      guard let date = parseGoTime(raw) else {
        throw DecodingError.dataCorrupted(.init(
          codingPath: decoder.codingPath,
          debugDescription: "unparseable timestamp \(raw)",
        ))
      }
      return date
    }
    return decoder
  }()

  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return encoder
  }()

  // MARK: Internal

  /// Go emits fractional seconds only when the time has them; each formatter accepts exactly one form.
  static func parseGoTime(_ raw: String) -> Date? {
    fractionalSeconds.withLock { $0.date(from: raw) }
      ?? wholeSeconds.withLock { $0.date(from: raw) }
  }

  // MARK: Private

  /// A decoder runs wherever its caller does — the event stream decodes off the main actor — so
  /// the two formatters are shared across tasks. Foundation does not declare `ISO8601DateFormatter`
  /// `Sendable`, and nothing else vouches for parsing through one from two tasks at once, so each
  /// is reached only under its own mutex rather than passed around as if it were a value.
  private static let fractionalSeconds = Mutex<ISO8601DateFormatter>({
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }())

  private static let wholeSeconds = Mutex<ISO8601DateFormatter>({
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }())

}

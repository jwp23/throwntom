import Foundation

/// JSON conventions of the throwntomd API: snake_case keys and Go RFC3339Nano timestamps.
public enum DaemonJSON {

  // MARK: Public

  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = goTime
    return decoder
  }()

  /// For bodies the daemon encodes straight from Go structs without tags (`/v1/stats`): field
  /// names are kept as written, only the timestamps need translating.
  public static let goFieldDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = goTime
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
    fractionalSeconds.date(from: raw) ?? wholeSeconds.date(from: raw)
  }

  // MARK: Private

  private static let goTime = JSONDecoder.DateDecodingStrategy.custom { decoder in
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let date = parseGoTime(raw) else {
      throw DecodingError.dataCorrupted(.init(
        codingPath: decoder.codingPath,
        debugDescription: "unparseable timestamp \(raw)",
      ))
    }
    return date
  }

  private static let fractionalSeconds: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let wholeSeconds: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

}

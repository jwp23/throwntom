import Foundation

/// A user-facing number of minutes: what one is called, how long one is allowed to be, and what
/// counts as one when it is typed. Snooze and meeting both ask the user for a length, and a rule
/// that differed between them would be a rule the user has to learn twice.
public enum Minutes {

  /// The longest length worth accepting. The daemon would take any positive number, but past a
  /// full day the entry is far likelier to be a typo than an intention, and neither a snooze nor
  /// a meeting nobody meant is visible until something fails to happen.
  public static let maximum = 1440

  /// Whole hours read as hours; everything else reads as minutes. "60 minutes" is a duration
  /// nobody says out loud, and the presets are chosen so this is the only case that arises.
  public static func title(_ minutes: Int) -> String {
    if minutes >= 60, minutes % 60 == 0 {
      let hours = minutes / 60
      return hours == 1 ? "1 hour" : "\(hours) hours"
    }
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }

  /// The minutes a typed entry asks for, or nil when it asks for nothing usable. Deliberately
  /// strict: only a whole number of minutes, so "10m" and "1.5" are refused rather than guessed at.
  public static func parse(_ text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber), let value = Int(trimmed) else { return nil }
    guard value > 0, value <= maximum else { return nil }
    return value
  }

}

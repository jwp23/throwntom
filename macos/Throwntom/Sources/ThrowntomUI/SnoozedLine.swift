import SwiftUI

/// The line that says a snooze is running. Snoozing withdraws the reminder banner, so this is the
/// only thing on screen that a deferred reminder has to show for itself.
struct SnoozedLine: View {

  // MARK: Internal

  /// The whole line, `Snoozed · MM:SS left`.
  let note: String
  /// The moving half on its own, so the line reads as a steady name with a value under it.
  let remaining: String?

  var body: some View {
    Text(note)
      .font(Self.font)
      // The window's second live countdown, read the same way as the headline: a steady name with
      // the minutes left as its value.
      .liveValue(label: Self.label, value: remaining)
  }

  // MARK: Private

  private static let font = Font.caption

  private static let label = "Snoozed"

}

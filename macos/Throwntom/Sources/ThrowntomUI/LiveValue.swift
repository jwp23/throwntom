import SwiftUI

// MARK: - LiveValue

/// A line whose name stays put while a number under it moves: the timer headline, and the snoozed
/// line. Both are read as one element with a steady label and a value that changes, rather than as
/// text that is silently different every time VoiceOver lands on it.
///
/// `.updatesFrequently` is the whole decision about a live countdown, and what it says is "this
/// value moves on its own; re-read it rather than trusting what I told you". It is not a request to
/// speak: nothing here announces a tick, and nothing should. A value rewritten every second,
/// announced, would be VoiceOver interrupting itself continuously and would drown the announcements
/// that do matter — the same judgement `ServiceAnnouncer` makes when it speaks only settled changes.
///
/// A line with nothing counting gets the label alone. Neither the value nor the trait is claimed
/// then: an empty value is a value the element does not have, and the trait would cost VoiceOver a
/// re-read of something that is not going to change.
struct LiveValue: ViewModifier {
  let label: String
  let value: String?

  /// What the line claims about itself. A property rather than written into `body` so the decision
  /// can be asserted directly; a SwiftUI modifier chain cannot be read back in a test process.
  var traits: AccessibilityTraits {
    value == nil ? [] : .updatesFrequently
  }

  func body(content: Content) -> some View {
    if let value {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(traits)
    } else {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
  }
}

extension View {
  /// Reads as `label`, with `value` as the part that moves. Nil `value` means nothing is counting.
  func liveValue(label: String, value: String?) -> some View {
    modifier(LiveValue(label: label, value: value))
  }
}

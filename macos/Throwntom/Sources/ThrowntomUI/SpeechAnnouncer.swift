import SwiftUI

// MARK: - SpeechAnnouncer

/// Whoever speaks a line to assistive technology. A protocol so the app's one side of the
/// conversation — which line, in which order, at which priority — can be asserted in a test
/// process, which is not allowed to reach VoiceOver itself.
/// `Sendable` with the isolation on the requirement rather than on the protocol, so a conforming
/// type can be constructed as a default argument — which is evaluated outside the main actor.
protocol SpeechAnnouncer: Sendable {
  @MainActor
  func speak(_ line: AttributedString)
}

// MARK: - SystemSpeechAnnouncer

/// The real thing. `.announcement` is the platform's own mechanism for a change that is not a
/// navigation: it does not move VoiceOver's cursor, so a user reading the focus list is told the
/// service went down without losing their place.
struct SystemSpeechAnnouncer: SpeechAnnouncer {
  func speak(_ line: AttributedString) {
    AccessibilityNotification.Announcement(line).post()
  }
}

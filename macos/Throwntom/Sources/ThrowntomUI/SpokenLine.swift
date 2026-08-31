import SwiftUI
import ThrowntomClient

/// How an announcement is dressed before it is posted.
enum SpokenLine {
  /// Turns a decided announcement into the attributed string the platform's announcement API
  /// takes, priority included.
  ///
  /// The priority is the whole reason this mapping exists rather than a bare `AttributedString`.
  /// A default-priority announcement is dropped when VoiceOver is already mid-utterance; the three
  /// service-down lines must not be dropped, because the window has just lost its timer service
  /// and there is no other signal that it has, so those interrupt. The transient dialling lines
  /// take the default and wait their turn: they must be said at the moment the window marks its
  /// title, but a blink of the socket is not worth cutting a reader off mid-sentence for.
  static func attributed(_ announcement: Announcement) -> AttributedString {
    var line = AttributedString(announcement.text)
    line.accessibilitySpeechAnnouncementPriority =
      switch announcement.priority {
      case .interrupting: .high
      case .queued: .default
      }
    return line
  }
}

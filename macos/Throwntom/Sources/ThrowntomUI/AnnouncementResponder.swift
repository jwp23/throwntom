import Observation
import SwiftUI
import ThrowntomClient

// MARK: - AnnouncementResponder

/// The app's whole side of telling assistive technology what happened to the timer service.
///
/// Follows the client rather than a view, for the same reason `ReminderResponder` does: what the
/// reader must be told does not depend on a window being on screen to render it. The window this
/// speaks for is a single window (ADR-005), so one responder is the whole app's memory of what has
/// already been said — the same memory that used to sit in `MainWindow`'s `@State`, where nothing
/// could reach it. It was reachable only through a SwiftUI `.onChange` a test process has no way
/// to fire, so deleting the entire modifier left the suite green (throwntom-9w9).
@MainActor
final class AnnouncementResponder {

  // MARK: Lifecycle

  init(client: DaemonClient, speaker: SpeechAnnouncer = SystemSpeechAnnouncer()) {
    self.client = client
    self.speaker = speaker
  }

  // MARK: Internal

  /// Takes the situation the app came up in as the baseline — which is deliberately silent — and
  /// begins following. The baseline is read here rather than left to the first change so that a
  /// service already down at launch is not announced as though it had just gone.
  func start() {
    follow()
    announce(client.serviceStatus)
  }

  /// Speaks a change of service situation, if this one is worth speaking about. What to say — and
  /// when to say nothing — is `ServiceAnnouncer`.
  func announce(_ status: ServiceStatus) {
    guard let announcement = announcer.announcement(for: status) else { return }
    speaker.speak(SpokenLine.attributed(announcement))
  }

  // MARK: Private

  private let client: DaemonClient
  private let speaker: SpeechAnnouncer

  /// Remembers which service situation was last worth speaking about.
  private var announcer = ServiceAnnouncer()

  /// Re-arms on every change, the way `withObservationTracking` requires: one registration fires
  /// once. Re-armed *before* the status is read, so a change landing during the hop is tracked
  /// rather than missed.
  ///
  /// Observation coalesces a burst into one callback, which is safe here rather than merely
  /// tolerable: `ServiceAnnouncer` folds each status against the last *settled* one instead of
  /// against its immediate predecessor, so a collapsed `running → reaching → notAnswering` still
  /// produces the line the reader is owed for where they have ended up.
  private func follow() {
    withObservationTracking {
      _ = client.serviceStatus
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        follow()
        announce(client.serviceStatus)
      }
    }
  }

}

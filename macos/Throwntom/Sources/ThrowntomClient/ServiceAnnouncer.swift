import Foundation

// MARK: - SpokenPriority

/// How hard a spoken line pushes to be heard.
///
/// Named here rather than taken from the platform's own announcement priority so this module stays
/// free of SwiftUI; `ThrowntomUI` maps it to the real thing when it posts.
public enum SpokenPriority: Sendable {
  /// Cuts across whatever assistive technology is currently reading. Reserved for the three
  /// service-down situations, where the whole window has just transformed and there is no other
  /// signal that it has.
  case interrupting
  /// Waits its turn, and is dropped rather than allowed to interrupt. What the transient dialling
  /// lines use: they must be said at the moment the window marks itself, but a blink of the socket
  /// is not worth cutting a reader off mid-sentence for.
  case queued
}

// MARK: - Announcement

/// One line to speak, and how hard it pushes.
public struct Announcement: Equatable, Sendable {

  public init(text: String, priority: SpokenPriority) {
    self.text = text
    self.priority = priority
  }

  public let text: String
  public let priority: SpokenPriority

}

// MARK: - ServiceAnnouncer

/// Turns the stream of service situations into the things worth saying about them.
///
/// The wording is `ServiceStatus.announcement(from:to:)` and `ServiceStatus.dialLine(from:)`; what
/// this adds is memory, and the memory is the whole difficulty. Every recovery reaches `.running`
/// through `.reaching`, so a rule reading only the immediately previous value cannot tell a Start
/// the user pressed and that worked — which they are owed, since silence after their own press
/// reads as a control that did nothing — from a blink of the socket. Remembering the last *settled*
/// situation separates them: the blip returns to the situation it left, the Start does not.
///
/// Both are spoken (throwntom-92i): the window marks its title `(reconnecting)` for the whole of a
/// blink, and Joe's ruling on throwntom-7rb is that the mark stands with no debounce, delay or
/// suppression. What the settled memory decides is the *wording and the priority*, not whether the
/// reader is told at all.
public struct ServiceAnnouncer: Sendable {

  // MARK: Lifecycle

  /// Empty on purpose, and required: Swift gives a public struct only an internal
  /// memberwise initialiser, so `ThrowntomUI` could not construct one without this.
  ///
  /// There is nothing to set. Both stored properties must start nil, and nil is what they
  /// already mean: no situation has been shown yet, so the next one is the baseline and is
  /// not spoken. Taking a status here would make the caller assert a starting point it does
  /// not have.
  public init() {
    // Nothing to set: `settled` and `previous` start nil, which is already the meaning wanted.
  }

  // MARK: Public

  /// What to speak now the service is in `status`, or nil for nothing worth saying.
  ///
  /// The first situation it is shown is the baseline and is never spoken: that one is the window
  /// coming up, which the reader is already reading, not something that changed under them.
  public mutating func announcement(for status: ServiceStatus) -> Announcement? {
    defer { previous = status }
    guard let settled else {
      // The window coming up. Whatever it came up in is the baseline, a dial included: a cold start
      // that ends in an absence has to be measured against the dial it began with, which is what
      // keeps arriving from that dial from reading as a recovery.
      settled = status
      return nil
    }
    let spoken = line(from: settled, to: status)
    // Dialling is never what a *later* change is measured against: it is the step every recovery
    // passes through, so recording it would erase the absence the recovery is recovering from.
    if status != .reaching {
      self.settled = status
    }
    return spoken
  }

  // MARK: Private

  /// The window's own word for the mark coming off the title, in the past tense its disappearance
  /// means.
  private static let reconnected = "Reconnected."

  private var settled: ServiceStatus?

  /// The situation shown immediately before this one, dialling included. Kept alongside `settled`
  /// because the two questions differ: `settled` is what a change is measured against, `previous`
  /// is whether this moment is the start of a dial or the end of one.
  private var previous: ServiceStatus?

  /// What this moment is worth saying, given what the reader was last told and what they were last
  /// shown. Reads `previous` before the caller advances it.
  private func line(from settled: ServiceStatus, to status: ServiceStatus) -> Announcement? {
    if status == .reaching {
      // One dial, one line. The backoff steps that follow are the same wait going on, and the
      // window's mark does not blink with them either.
      guard previous != .reaching else { return nil }
      return Announcement(text: ServiceStatus.dialLine(from: settled), priority: .queued)
    }
    // A dial that ended where it began. `announcement(from:to:)` has nothing to say about it —
    // `from` and `to` are the same situation — so without this the wait would be announced when it
    // began and then never resolved aloud, leaving the reader on a wait the window has visibly
    // finished with.
    //
    // Every situation can be arrived back at, not just a running one: `startService()` clears
    // `startStalled` (`DaemonClient.startService`), so pressing Start Timer Service on the
    // unanswered screen dials and a launch that goes unanswered again lands straight back there.
    //
    // Returning to a running service is the blip, and stays queued with the rest of the dial.
    // Returning to an absence is the answer to a press the user made, and interrupts like every
    // other line about a service that is not there.
    if previous == .reaching, status == settled {
      return status == .running
        ? Announcement(text: Self.reconnected, priority: .queued)
        : ServiceStatus.settledLine(for: status).map { Announcement(text: $0, priority: .interrupting) }
    }
    return ServiceStatus.announcement(from: settled, to: status)
      .map { Announcement(text: $0, priority: .interrupting) }
  }

}

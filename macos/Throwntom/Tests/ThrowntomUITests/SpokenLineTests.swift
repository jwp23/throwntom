import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// How a decided announcement is dressed before it is posted. The priority is the whole reason the
/// mapping exists: it is what keeps a socket blip from cutting a reader off while still letting a
/// service that has gone interrupt.
@MainActor
final class SpokenLineTests: XCTestCase {

  /// A default-priority announcement is dropped when VoiceOver is already speaking. The three
  /// service-down lines must not be dropped: the window has just lost its timer, and the reader
  /// has no other signal. High priority interrupts instead, which is the right trade for an event
  /// this rare and this consequential — `ServiceAnnouncer` is what keeps it rare.
  func testAServiceDownLineInterruptsRatherThanQueueingBehindWhateverIsBeingRead() {
    let spoken = SpokenLine.attributed(Announcement(text: "Timer service stopped.", priority: .interrupting))

    XCTAssertEqual(spoken.accessibilitySpeechAnnouncementPriority, .high)
    XCTAssertEqual(String(spoken.characters), "Timer service stopped.")
  }

  /// The other half of the same trade (throwntom-92i): the reconnect mark is spoken the instant it
  /// appears, but a blink of the socket must not cut a reader off mid-sentence, so its line waits
  /// its turn and is dropped rather than allowed to interrupt.
  func testATransientLineWaitsItsTurnInsteadOfInterrupting() {
    let spoken = SpokenLine.attributed(Announcement(text: "Reconnecting.", priority: .queued))

    XCTAssertEqual(spoken.accessibilitySpeechAnnouncementPriority, .default)
    XCTAssertEqual(String(spoken.characters), "Reconnecting.")
  }

}

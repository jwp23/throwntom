import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// The platform's own priority, named once so the assertions below read as the three words it has.
typealias SpeechPriority = AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute.AnnouncementPriority

// MARK: - RecordingSpeaker

/// Records what the app asked assistive technology to say, so the line, its order and its priority
/// can be checked without VoiceOver, which no test process may reach.
@MainActor
final class RecordingSpeaker: SpeechAnnouncer {
  struct Spoken: Equatable {
    let text: String
    let priority: SpeechPriority?
  }

  private(set) var spoken = [Spoken]()

  var lines: [String] {
    spoken.map(\.text)
  }

  func speak(_ line: AttributedString) {
    spoken.append(Spoken(text: String(line.characters), priority: line.accessibilitySpeechAnnouncementPriority))
  }
}

// MARK: - DroppedConnectionTransport

/// A socket that answers once and then goes, the way it does when the daemon is restarted under a
/// running client. `StubTransport` holds its stream open instead, which is the connected case; this
/// is the one that takes the window from running to dialling.
final class DroppedConnectionTransport: DaemonTransport, Sendable {

  // MARK: Lifecycle

  init(state: DaemonState) {
    frame = (try? daemonEncoder.encode(state)) ?? Data()
  }

  // MARK: Internal

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    HTTPResponse(status: 200, headers: [:], body: Data(#"{"message":"ok"}"#.utf8))
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(frame)
      continuation.finish(throwing: DaemonError.transport("dropped"))
    }
  }

  // MARK: Private

  private let frame: Data

}

// MARK: - AnnouncementResponderTests

/// throwntom-9w9. What used to connect `ServiceAnnouncer` to the platform was a SwiftUI
/// `.onChange` inside `MainWindow.body` — a declarative binding no test process can fire. Deleting
/// the whole modifier left all 567 tests green, so the announcer's wording was proven and nothing
/// proved the app ever asked it anything.
///
/// Following the client directly is what makes the wiring reachable. These drive a real
/// `DaemonClient` over a real transport and assert on the lines that came out the far end.
///
/// What no test here can show is that macOS then speaks them: posting an accessibility
/// announcement is a request to a screen reader that is not running in this process.
@MainActor
final class AnnouncementResponderTests: XCTestCase {

  // MARK: Internal

  /// The whole chain, end to end and without a view: a real client over a socket that connects and
  /// then drops, an observation that notices, the announcer that decides, and the line that comes
  /// out the far end. Nothing here calls `announce` by hand — starting the environment is the only
  /// thing this test does, which is the wiring that used to be unreachable.
  func testTheAppSpeaksALostConnectionWithoutAWindowToRenderIt() async throws {
    let speaker = RecordingSpeaker()
    let environment = AppEnvironment(transport: DroppedConnectionTransport(state: makeState(phase: .work)), speaker: speaker)
    defer { shutDown(environment) }

    environment.start()

    try await waitUntil { !speaker.spoken.isEmpty }
    XCTAssertEqual(
      speaker.spoken.first,
      .init(text: "Reconnecting.", priority: .default),
      "the window marks its title (reconnecting) at this moment and the reader is owed the same fact",
    )
  }

  /// The `.onChange` this replaces was the only thing that ever called the announcer, and it ran
  /// only while the window was rendering. Starting the environment is now what arms it, so the
  /// baseline is taken from the situation the app came up in rather than from the first render.
  func testStartingTheAppTakesTheSituationItCameUpInAsTheBaseline() async throws {
    let speaker = RecordingSpeaker()
    let environment = AppEnvironment(transport: UnreachableDaemonTransport(), speaker: speaker)
    defer { shutDown(environment) }

    environment.start()
    try await waitUntil { environment.client.serviceStatus != .running }

    XCTAssertEqual(speaker.lines, [], "the app opening onto a dial is not something that changed")
  }

  /// throwntom-92i, through the wiring rather than the wording: the mark the window puts on its
  /// title is spoken at the moment it appears, and again when it goes.
  func testTheReconnectMarkIsSpokenAtBothEdges() throws {
    let speaker = RecordingSpeaker()
    let responder = try makeResponder(speaker)

    responder.announce(.running)
    responder.announce(.reaching)
    responder.announce(.running)

    XCTAssertEqual(speaker.spoken, [
      .init(text: "Reconnecting.", priority: .default),
      .init(text: "Reconnected.", priority: .default),
    ])
  }

  /// The dressing and the decision have to stay joined: a `.high` line on a socket blip would cut
  /// a reader off every time the network hiccupped, and a `.default` line on a service that has
  /// gone would be dropped exactly when VoiceOver is busy saying something else.
  func testTheThreeServiceDownLinesInterruptAndTheTransientOnesDoNot() throws {
    let speaker = RecordingSpeaker()
    let responder = try makeResponder(speaker)

    responder.announce(.running)
    responder.announce(.reaching)
    responder.announce(.notAnswering)

    XCTAssertEqual(speaker.spoken.map(\.priority), [.default, .high])
    XCTAssertEqual(speaker.lines.last, "Timer service isn\u{2019}t answering. " + (
      try XCTUnwrap(ServiceStatus.notAnswering.explanation)
    ))
  }

  /// Nothing is spoken for a situation that has not changed, however many frames report it. The
  /// client republishes its status on every frame, so without this the reader would be told the
  /// same thing once a second.
  func testAnUnchangedSituationIsNeverRepeated() throws {
    let speaker = RecordingSpeaker()
    let responder = try makeResponder(speaker)

    responder.announce(.running)
    for _ in 0..<10 {
      responder.announce(.stopped)
    }

    XCTAssertEqual(speaker.lines.count, 1)
  }

  // MARK: Private

  private func makeResponder(_ speaker: RecordingSpeaker) throws -> AnnouncementResponder {
    let environment = AppEnvironment(transport: try StubTransport(states: []), speaker: speaker)
    return AnnouncementResponder(client: environment.client, speaker: speaker)
  }

  private func shutDown(_ environment: AppEnvironment) {
    environment.client.stop()
    environment.ticker.stop()
  }

}

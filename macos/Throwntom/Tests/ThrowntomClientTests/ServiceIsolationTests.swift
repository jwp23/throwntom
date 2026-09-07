import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - ServiceRegistrationIsolationTests

/// throwntom-339. The client is `@MainActor`, so anything it calls without awaiting runs where the
/// window is drawn. Driving launchd is `Process` and `waitUntilExit`, up to four of them for one
/// registration, which is a frozen window for as long as launchd takes.
@MainActor
final class ServiceRegistrationIsolationTests: XCTestCase {

  func testPressingStartDoesNotDriveLaunchdOnTheMainActor() async {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)

    await client.startService()
    defer { client.stop() }

    XCTAssertEqual(registrar.calls, [.register])
    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

  func testPressingStopDoesNotDriveLaunchdOnTheMainActor() async {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: StubStateTransport(), registrar: registrar)

    await client.stopService()

    XCTAssertEqual(registrar.calls, [.stop])
    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

  /// The site the bug was found at: the reconnect loop asks launchd for the daemon after three
  /// failed dials, and it does that from the same main actor the window is drawn on.
  func testTheReconnectLoopDoesNotDriveLaunchdOnTheMainActor() async throws {
    let registrar = RecordingRegistrar()
    let client = DaemonClient(transport: OutageTransport(), registrar: registrar, backoff: [.milliseconds(5)])
    client.start()
    defer { client.stop() }

    try await waitUntil("the loop to ask launchd for the daemon") { registrar.registrations == 1 }

    XCTAssertEqual(registrar.mainThreadCalls, [false])
  }

}

// MARK: - ServiceVerbSerialisationTests

/// Start and Stop each contact launchd and then write the connection state that follows from what
/// launchd did. Nothing may get between those two halves. While the launchd calls blocked the main
/// actor nothing could, so the ordering came for nothing; awaiting them is what lets a second
/// press in, and the ordering now has to be kept on purpose.
@MainActor
final class ServiceVerbSerialisationTests: XCTestCase {

  /// The interleaving that reaches ADR-010: the Stop finishes last, so it writes the stopped
  /// ending over a stream the Start opened while it was waiting on launchd. The service the user
  /// stopped goes on dialling, and asks launchd for the daemon back on its third failed dial.
  func testAStopPressedInsideAStartLeavesTheServiceStopped() async throws {
    let registrar = SlowLaunchdRegistrar(registering: .milliseconds(100), stopping: .milliseconds(300))
    let client = DaemonClient(transport: VanishingTransport(), registrar: registrar, backoff: [.milliseconds(5)])
    defer { client.stop() }

    let starting = Task { await client.startService() }
    try await waitUntil("the start to reach launchd") { registrar.isRegistering }
    await client.stopService()
    await starting.value

    // Long enough for a stream the Start left behind to fail its way to the third dial that asks
    // launchd for the daemon back.
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertEqual(client.connection, .stopped)
    XCTAssertNil(client.state, "a stopped service has no phase to show")
    XCTAssertEqual(registrar.registrations, 1, "the loop asked launchd for the service the user stopped")
  }

  /// The mirror, where the Start finishes last. It is the later of the two presses, so it is the
  /// one that decides the outcome; the Stop must not write its own ending over it.
  func testAStartPressedInsideAStopLeavesTheServiceRunning() async throws {
    let registrar = SlowLaunchdRegistrar(registering: .milliseconds(100), stopping: .milliseconds(300))
    let client = DaemonClient(transport: CountingStateTransport(), registrar: registrar)
    defer { client.stop() }

    let stopping = Task { await client.stopService() }
    try await waitUntil("the stop to reach launchd") { registrar.isStopping }
    await client.startService()
    await stopping.value

    XCTAssertNotEqual(client.connection, .stopped)
    try await waitUntil("the restarted client to reach the daemon") { client.connection == .connected }
  }

}

// MARK: - SlowLaunchdRegistrar

/// A launchd stand-in whose calls take long enough for a second press to land inside them, the way
/// a real `bootstrap` and `bootout` do. The two durations are given separately because which of
/// the two verbs finishes last is the whole of the interleaving under test.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class SlowLaunchdRegistrar: LaunchAgentRegistrar, @unchecked Sendable {

  // MARK: Lifecycle

  init(registering: Duration, stopping: Duration) {
    registerDuration = registering
    stopDuration = stopping
  }

  // MARK: Internal

  var isRegistering: Bool {
    lock.withLock { registering }
  }

  var isStopping: Bool {
    lock.withLock { stopping }
  }

  var registrations: Int {
    lock.withLock { registered }
  }

  func ensureAgentRegistered() async throws {
    lock.withLock { registering = true }
    try? await Task.sleep(for: registerDuration)
    lock.withLock {
      registering = false
      registered += 1
    }
  }

  func stopAgent() async throws {
    lock.withLock { stopping = true }
    try? await Task.sleep(for: stopDuration)
    lock.withLock { stopping = false }
  }

  // MARK: Private

  private let registerDuration: Duration
  private let stopDuration: Duration
  private let lock = NSLock()
  private var registering = false
  private var stopping = false
  private var registered = 0

}

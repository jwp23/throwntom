import Foundation
import XCTest
@testable import ThrowntomClient

// MARK: - ServiceIntentStoreTests

/// Where "the user stopped the timer service" is written down, so a relaunch can read it back.
final class ServiceIntentStoreTests: XCTestCase {

  // MARK: Internal

  override func tearDown() {
    if let suite {
      UserDefaults.standard.removePersistentDomain(forName: suite)
    }
    suite = nil
    super.tearDown()
  }

  /// A first launch has recorded nothing, and neither has a client whose daemon died. Both want
  /// the daemon; only an explicit Stop does not, which is why absence has to read as running.
  func testNothingRecordedMeansTheServiceShouldRun() throws {
    XCTAssertEqual(try makeStore().loadIntent(), .running)
  }

  func testAStoppedIntentIsStillStoppedOnTheNextLaunch() throws {
    let store = try makeStore()
    store.save(.stopped)

    XCTAssertEqual(try reopened().loadIntent(), .stopped)
  }

  func testStartingAgainClearsTheStoppedIntent() throws {
    let store = try makeStore()
    store.save(.stopped)
    store.save(.running)

    XCTAssertEqual(try reopened().loadIntent(), .running)
  }

  /// A value nobody wrote — a hand-edited plist, a key another build used — is not an
  /// instruction to keep the timer down.
  func testAnUnreadableRecordMeansTheServiceShouldRun() throws {
    let name = try suiteName()
    try XCTUnwrap(UserDefaults(suiteName: name)).set("banana", forKey: UserDefaultsServiceIntentStore.key)

    XCTAssertEqual(try reopened().loadIntent(), .running)
  }

  // MARK: Private

  private var suite: String?

  private func suiteName() throws -> String {
    if let suite {
      return suite
    }
    let name = "throwntom.tests.\(UUID().uuidString)"
    suite = name
    return name
  }

  private func makeStore() throws -> UserDefaultsServiceIntentStore {
    UserDefaultsServiceIntentStore(defaults: try XCTUnwrap(UserDefaults(suiteName: try suiteName())))
  }

  /// A second store over the same suite: what the next launch of the app reads.
  private func reopened() throws -> UserDefaultsServiceIntentStore {
    try makeStore()
  }

}

// MARK: - PersistedStopTests

/// throwntom-faa. A stop is a deliberate act, so it survives a relaunch and the reconnect loop
/// must not undo it. The failure it replaces was silent: three failed dials asked launchd for the
/// daemon again, and the app came back with the service the user had switched off.
@MainActor
final class PersistedStopTests: XCTestCase {

  func testStoppingTheServiceRecordsTheIntent() async throws {
    let intents = FakeIntentStore(.running)
    let client = DaemonClient(transport: StubStateTransport(), registrar: RecordingRegistrar(), intents: intents)
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stopService()

    XCTAssertEqual(intents.saved, [.stopped])
  }

  /// Nothing changed, so nothing is recorded: a refused stop leaves a daemon still running, and a
  /// stopped intent written here would take it down on the next launch instead.
  func testARefusedStopRecordsNothing() async throws {
    let intents = FakeIntentStore(.running)
    let client = DaemonClient(
      transport: StubStateTransport(),
      registrar: RecordingRegistrar(stopError: RecordingRegistrar.Denied()),
      intents: intents,
    )
    client.start()
    try await waitUntil("the initial state to arrive") { client.state != nil }

    client.stopService()

    XCTAssertEqual(intents.saved, [])
  }

  func testStartingTheServiceRecordsThatItShouldRunAgain() {
    let intents = FakeIntentStore(.stopped)
    let client = DaemonClient(transport: StubStateTransport(), registrar: RecordingRegistrar(), intents: intents)

    client.startService()

    XCTAssertEqual(intents.saved, [.running])
  }

  /// The whole point of the ruling. On this launch the client must not dial, must not count
  /// failures, and above all must not ask launchd for the daemon the user switched off.
  func testALaunchWithAStoppedIntentNeitherDialsNorRegisters() async throws {
    let transport = CountingTransport()
    let registrar = RecordingRegistrar()
    let client = DaemonClient(
      transport: transport,
      registrar: registrar,
      backoff: [.milliseconds(5)],
      intents: FakeIntentStore(.stopped),
    )

    client.start()
    try await Task.sleep(for: .milliseconds(300))

    XCTAssertEqual(registrar.calls, [], "the reconnect loop asked launchd for a service the user stopped")
    XCTAssertEqual(transport.streamsOpened, 0, "a stopped service is not dialled")
    client.stop()
  }

  func testALaunchWithAStoppedIntentSaysSoRatherThanConnecting() {
    let client = DaemonClient(
      transport: CountingTransport(),
      registrar: RecordingRegistrar(),
      intents: FakeIntentStore(.stopped),
    )

    XCTAssertEqual(client.connection, .stopped)
    XCTAssertEqual(client.serviceStatus, .stopped)
    XCTAssertNil(client.unresolvedError, "stopping on purpose is not an error to report on the next launch")
  }

  /// The states this one has to stay distinguishable from: a first launch has recorded nothing,
  /// and a client whose daemon died has an intent of running. Both dial; only a stop does not.
  func testALaunchWithNoStoppedIntentDialsAsUsual() async throws {
    let transport = CountingTransport()
    let client = DaemonClient(
      transport: transport,
      registrar: RecordingRegistrar(),
      backoff: [.milliseconds(5)],
      intents: FakeIntentStore(.running),
    )

    XCTAssertEqual(client.connection, .connecting)
    client.start()
    defer { client.stop() }

    try await waitUntil("the client to dial") { transport.streamsOpened > 0 }
  }

  /// Pressing Start after a persisted stop has to leave the stopped footing behind entirely,
  /// not just record a new intent.
  func testStartingAfterAPersistedStopDialsAgain() async throws {
    let transport = CountingTransport()
    let client = DaemonClient(
      transport: transport,
      registrar: RecordingRegistrar(),
      backoff: [.milliseconds(5)],
      intents: FakeIntentStore(.stopped),
    )
    client.start()

    client.startService()
    defer { client.stop() }

    try await waitUntil("the restarted client to dial") { transport.streamsOpened > 0 }
    XCTAssertNotEqual(client.connection, .stopped)
  }

}

// MARK: - FakeIntentStore

/// The recorded intent, in memory, so a test can start a client on either footing without
/// touching the user defaults of the machine running it.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class FakeIntentStore: ServiceIntentStore, @unchecked Sendable {

  // MARK: Lifecycle

  init(_ intent: ServiceIntent) {
    stored = intent
  }

  // MARK: Internal

  /// Every intent written, in order, so a test can tell "recorded running" from "recorded
  /// nothing" — which is the difference between honouring a refused stop and undoing it.
  var saved: [ServiceIntent] {
    lock.withLock { writes }
  }

  func loadIntent() -> ServiceIntent {
    lock.withLock { stored }
  }

  func save(_ intent: ServiceIntent) {
    lock.withLock {
      stored = intent
      writes.append(intent)
    }
  }

  // MARK: Private

  private let lock = NSLock()
  private var stored: ServiceIntent
  private var writes = [ServiceIntent]()

}

// MARK: - CountingTransport

/// A daemon that is not there, which counts the dials so a test can assert there were none.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class CountingTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Internal

  var streamsOpened: Int {
    lock.withLock { opened }
  }

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    throw Self.gone
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    lock.withLock { opened += 1 }
    return AsyncThrowingStream { continuation in
      continuation.finish(throwing: Self.gone)
    }
  }

  // MARK: Private

  private static let gone = DaemonError.transport("POSIXErrorCode(rawValue: 2): No such file or directory")

  private let lock = NSLock()
  private var opened = 0

}

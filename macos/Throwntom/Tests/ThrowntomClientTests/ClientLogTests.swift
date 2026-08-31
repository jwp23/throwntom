import XCTest
@testable import ThrowntomClient

// MARK: - LogRecorder

/// Captures what the app would have written to the unified log. The sink is the only way to see
/// that a catch site recorded anything: `os.Logger` writes where a test process cannot read back.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class LogRecorder: @unchecked Sendable {

  // MARK: Lifecycle

  init() {
    previous = ClientLog.sink
    ClientLog.sink = { [self] entry in
      lock.withLock { recorded.append(entry) }
    }
  }

  deinit {
    ClientLog.sink = previous
  }

  // MARK: Internal

  var entries: [ClientLog.Entry] {
    lock.withLock { recorded }
  }

  var messages: [String] {
    entries.map(\.message)
  }

  /// The one entry recorded, or a test failure naming what was recorded instead.
  func onlyEntry(file: StaticString = #filePath, line: UInt = #line) throws -> ClientLog.Entry {
    let all = entries
    guard all.count == 1, let entry = all.first else {
      XCTFail("expected exactly one log entry, got \(all)", file: file, line: line)
      throw NothingRecorded()
    }
    return entry
  }

  // MARK: Private

  private struct NothingRecorded: Error { }

  private let previous: @Sendable (ClientLog.Entry) -> Void
  private let lock = NSLock()
  private var recorded = [ClientLog.Entry]()

}

// MARK: - ClientLogTests

/// The diagnostic channel a failure leaves behind. The window's sentence stays as it is
/// (throwntom-e5s); this is where the shape of the failure goes instead of nowhere (throwntom-zas).
final class ClientLogTests: XCTestCase {

  func testTheSubsystemIsTheAppsBundleIdentifier() {
    // What `log show --predicate 'subsystem == "…"'` in docs/development.md is filtering on, and
    // what macos/bundle/Info.plist declares. A drift between the two makes the documented command
    // return nothing.
    XCTAssertEqual(ClientLog.subsystem, "com.jwp23.throwntom")
  }

  func testEveryAreaIsALowercaseCategoryName() {
    // Each becomes a `category` in `log show`; the docs list them, so they must stay typeable.
    XCTAssertEqual(
      Set(ClientLog.Area.allCases.map(\.rawValue)),
      ["daemon", "service", "reminders", "tasks", "stats"],
    )
  }

  /// The rule the whole seam exists under: the daemon quotes the user's own words back in its
  /// error replies (`unknown command: %s`, internal/core/core.go), and those arrive as
  /// `DaemonError.http`'s message. Logging that message would put task text in the system log.
  func testAnHTTPFailureLogsItsStatusAndNeverTheDaemonsMessage() {
    let described = ClientLog.describe(
      DaemonError.http(status: 409, message: "unknown command: buy oat milk for Ada")
    )

    XCTAssertEqual(described, "http 409")
    XCTAssertFalse(described.contains("oat milk"), described)
    XCTAssertFalse(described.contains("Ada"), described)
  }

  func testATransportFailureKeepsTheReasonTheClientItselfWrote() {
    XCTAssertEqual(ClientLog.describe(DaemonError.transport("no daemon")), "transport: no daemon")
  }

  func testAMalformedResponseKeepsTheReasonTheClientItselfWrote() {
    XCTAssertEqual(
      ClientLog.describe(DaemonError.malformedResponse("response ended before headers completed")),
      "malformed response: response ended before headers completed",
    )
  }

  func testATimeoutSaysHowLongItWaited() {
    XCTAssertEqual(ClientLog.describe(DaemonError.timedOut(after: .seconds(5))), "timed out after 5s")
  }

  func testACancellationIsNamedRatherThanDescribedAsAFault() {
    XCTAssertEqual(ClientLog.describe(CancellationError()), "cancelled")
  }

  /// A framework error — `SMAppServiceErrorDomain error 1`, a `UNError` — is kept as the two
  /// things that identify it. Its `localizedDescription` is deliberately not read: that is the
  /// text the window rule keeps out of this app, and it carries no more than the domain and code.
  func testAFrameworkErrorIsKeptAsItsDomainAndCode() {
    let error = NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "The operation couldn't be completed."
    ])

    XCTAssertEqual(ClientLog.describe(error), "SMAppServiceErrorDomain 1")
  }

  func testAnEnumErrorOfOursIsKeptAsItsTypeAndCase() {
    // Bridged to NSError, a Swift enum error gives the type's name and the case's index, and
    // never an associated value — which is what keeps a payload of user text out of the log.
    let described = ClientLog.describe(TaskCommandError.controlCharacters)

    XCTAssertTrue(described.contains("TaskCommandError"), described)
  }

  func testAFailureRecordsTheOperationAndTheShapeOfTheError() throws {
    let recorder = LogRecorder()

    ClientLog.failed("send a timer verb", in: .daemon, error: DaemonError.http(status: 409, message: "no"))

    let entry = try recorder.onlyEntry()
    XCTAssertEqual(entry.area, .daemon)
    XCTAssertEqual(entry.message, "send a timer verb failed: http 409")
  }

}

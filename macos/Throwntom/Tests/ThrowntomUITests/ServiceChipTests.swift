import ThrowntomClient
import XCTest
@testable import ThrowntomUI

/// The window's own Start/Stop control for the timer service (ADR-006). Every client here is
/// built on a fake registrar, so no test registers or boots out a launchd agent.
@MainActor
final class ServiceChipTests: XCTestCase {

  // MARK: Internal

  func testStoppedServiceOffersStartAsThePrimaryChip() {
    let content = serviceContent(connection: .stopped)
    XCTAssertEqual(content.title, "Timer service stopped")
    XCTAssertEqual(content.serviceAction, .start)
    XCTAssertEqual(content.chips, [], "a stopped service has no timer verbs to offer")

    let chip = ServiceChip(content: content, client: client()).chip
    XCTAssertEqual(chip.title, "Start Timer Service")
    XCTAssertEqual(chip.style, ChipStyle.style(primary: true, scheme: content.scheme))
  }

  func testRunningServiceOffersStopAsASecondaryChip() {
    let content = serviceContent(state: makeState(phase: .work), connection: .connected)
    XCTAssertEqual(content.serviceAction, .stop)

    let chip = ServiceChip(content: content, client: client()).chip
    XCTAssertEqual(chip.title, "Stop Timer Service")
    XCTAssertEqual(chip.style, ChipStyle.style(primary: false, scheme: content.scheme))
  }

  func testTappingStartAsksLaunchdForTheDaemon() {
    let registrar = RecordingRegistrar()
    let chip = ServiceChip(content: serviceContent(connection: .stopped), client: client(registrar)).chip

    chip.action()

    XCTAssertEqual(registrar.calls, [.register])
  }

  func testTappingStopBootsTheAgentOut() {
    let registrar = RecordingRegistrar()
    let content = serviceContent(state: makeState(phase: .work), connection: .connected)
    let chip = ServiceChip(content: content, client: client(registrar)).chip

    chip.action()

    XCTAssertEqual(registrar.calls, [.stop])
  }

  /// throwntom-jtx: a refused launch renders as the failure it is, and the control it points at
  /// is this same chip rather than a retry button built only for that state.
  func testARefusedLaunchNamesTheFailureAndOffersStart() {
    let content = serviceContent(connection: .startingDaemon, registrationFailed: true)
    XCTAssertEqual(content.title, "Timer service can\u{2019}t launch")
    XCTAssertEqual(content.serviceAction, .start)

    let chip = ServiceChip(content: content, client: client()).chip
    XCTAssertEqual(chip.title, "Start Timer Service")
    XCTAssertEqual(chip.style, ChipStyle.style(primary: true, scheme: content.scheme))
  }

  func testServiceChipBuilds() {
    _ = ServiceChip(content: serviceContent(connection: .stopped), client: client()).body
  }

  // MARK: Private

  /// Every client here is torn down with the test: `startService()` starts a real reconnect loop,
  /// and a stream task that outlives its test is a flake waiting to happen.
  private func client(_ registrar: RecordingRegistrar = RecordingRegistrar()) -> DaemonClient {
    let client = DaemonClient(transport: UnreachableDaemonTransport(), registrar: registrar)
    addTeardownBlock { @MainActor in client.stop() }
    return client
  }

  private func serviceContent(
    state: DaemonState? = nil,
    connection: DaemonClient.Connection,
    registrationFailed: Bool = false,
  ) -> MainWindowContent {
    MainWindowContent(
      state: state,
      connection: connection,
      tasks: TaskList(),
      error: nil,
      registrationFailed: registrationFailed,
      panel: nil,
      now: .now,
    )
  }

}

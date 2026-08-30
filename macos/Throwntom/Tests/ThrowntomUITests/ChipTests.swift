// Tests/ThrowntomUITests/ChipTests.swift
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class ChipTests: XCTestCase {
  func testPrimaryChipIsOutlineOnCream() {
    let scheme = Palette.scheme(for: .idle)
    XCTAssertEqual(
      ChipStyle.style(primary: true, scheme: scheme),
      ChipStyle(fill: scheme.primaryChip, text: scheme.primaryChipText),
    )
    XCTAssertEqual(
      ChipStyle.style(primary: false, scheme: scheme),
      ChipStyle(fill: scheme.secondaryChip, text: scheme.secondaryChipText),
    )
  }

  func testDispatchSendsTheVerbToTheDaemon() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    DaemonDispatch.perform(.start, on: environment.client)
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/start"])
  }

  func testDispatchSendsACommandLine() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    DaemonDispatch.send("task done 1", to: environment.client)
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/command"])
    XCTAssertEqual(transport.commands.first?.body, #"{"line":"task done 1"}"#)
  }

  func testChipBodiesBuild() throws {
    let scheme = Palette.scheme(for: .work)
    _ = Chip(title: "Pause", hint: "⌘P", isPrimary: false, scheme: scheme) { }.body
    _ = Chip(title: "Skip Today", hint: "", isPrimary: false, scheme: scheme) { }.body
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    _ = ActionChips(content: content, client: environment.client).body
  }

  /// A plain `HStack` ran the timer verbs past the edge of a 320pt window. The row is built from
  /// `BlockFlowLayout` instead, which puts `_LayoutRoot<BlockFlowLayout>` in the body's type where
  /// an `HStack` would name itself — so this fails if the row goes back to a stack. The wrapping
  /// itself is `BlockFlowLayoutTests`; what is asserted here is that the timer row goes through it.
  func testTimerChipsFlowRatherThanSitInOneStack() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )

    let timerRow = String(describing: type(of: ActionChips(content: content, client: environment.client).body))
    let commandRow = String(
      describing: type(of: CommandChips(environment: environment, scheme: content.scheme).body)
    )

    XCTAssertTrue(timerRow.contains("_LayoutRoot<BlockFlowLayout>"), timerRow)
    XCTAssertTrue(commandRow.contains("_LayoutRoot<BlockFlowLayout>"), "both chip rows flow: \(commandRow)")
  }

  func testChipForActionMatchesTheActionAndDispatchesOnTap() async throws {
    let transport = try StubTransport(states: [makeState(phase: .idle)])
    let environment = AppEnvironment(transport: transport)
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    let content = MainWindowContent(
      state: makeState(phase: .awaitingConfirm),
      connection: .connected,
      status: .running,
      tasks: TaskList(),
      error: nil,
      panel: nil,
      now: .now,
    )
    let chips = ActionChips(content: content, client: environment.client)
    let primary = chips.chip(for: .confirm)
    XCTAssertEqual(primary.title, TimerAction.confirm.title)
    XCTAssertEqual(primary.style, ChipStyle.style(primary: true, scheme: content.scheme))

    primary.action()
    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.map(\.path), ["/v1/timer/confirm"])
  }
}

import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - ServiceDownMenuTests

/// Every menu that dispatches to the daemon, on each of the three screens where there is no
/// daemon to dispatch to. The window was fixed first and the menus were not, which was worse
/// rather than merely incomplete: a key equivalent fires with no control on screen to look wrong.
@MainActor
final class ServiceDownMenuTests: XCTestCase {

  // MARK: Internal

  /// The retained state is the point. It is still there — the menus, the cheat sheet and the
  /// focus list read it, and a view must not blank the model to dress itself — so enablement has
  /// to be told the service is gone rather than infer it from an empty state.
  func testTheTimerMenuOffersNothingOnAnyScreenWithoutADaemon() {
    for status in Self.absent {
      let menu = MenuModel.timer(
        state: makeState(phase: .work),
        returnIsTaken: false,
        daemonAvailable: status.offersDaemonCommands,
      )

      XCTAssertFalse(menu.items.isEmpty, "\(status)")
      XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled }, "\(status): ⌘⇧P and ⌘K would fire into nothing")
    }
  }

  func testTheTimerMenuIsUntouchedWhileTheDaemonIsMerelyBeingDialled() {
    let dialling = MenuModel.timer(state: makeState(phase: .work), returnIsTaken: false, daemonAvailable: true)

    XCTAssertEqual(enabled(dialling), [.pause, .skip, .skipToday, .lunch])
  }

  /// Every task verb is a command line for the daemon (`TaskActionDispatch.run`), including the
  /// one that opens the inline editor, whose whole purpose is to send one.
  func testTheTasksMenuOffersNothingOnAnyScreenWithoutADaemon() {
    for status in Self.absent {
      let menu = MenuModel.tasks(model: modelWithATask(), daemonAvailable: status.offersDaemonCommands)

      XCTAssertFalse(menu.items.isEmpty, "\(status)")
      XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled }, "\(status)")
    }
  }

  func testTheTasksMenuIsUntouchedWhileTheDaemonIsThere() {
    let menu = MenuModel.tasks(model: modelWithATask(), daemonAvailable: true)

    XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
  }

  /// Decided per command rather than blanket-disabled: the cheat sheet and the config file are
  /// local and stay useful with no daemon, and taking them away would punish the reader for an
  /// outage they are trying to understand.
  func testTheViewMenuKeepsItsLocalCommandAndDropsTheDaemonBackedOnes() throws {
    for status in Self.absent {
      let menu = MenuModel.view(showsShortcuts: false, daemonAvailable: status.offersDaemonCommands)

      XCTAssertFalse(try XCTUnwrap(menu.item(for: .tasks)).isEnabled, "\(status)")
      XCTAssertFalse(try XCTUnwrap(menu.item(for: .stats)).isEnabled, "\(status)")
      XCTAssertTrue(try XCTUnwrap(menu.item(for: .shortcuts)).isEnabled, "\(status): the cheat sheet is local")
    }
  }

  func testTheCommandChipRowKeepsItsLocalCommandsAndDropsTheDaemonBackedOnes() throws {
    let menu = MenuModel.windowCommands(model: WindowModel(), daemonAvailable: false)

    XCTAssertEqual(menu.items.map(\.action), [.tasks, .stats, .shortcuts, .openConfig], "the row still lists them all")
    XCTAssertFalse(try XCTUnwrap(menu.item(for: .tasks)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(menu.item(for: .stats)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(menu.item(for: .shortcuts)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(menu.item(for: .openConfig)).isEnabled, "editing the config is how an outage gets fixed")
  }

  /// The one control that has to work when nothing else does.
  func testTheServiceToggleStaysLiveOnEveryScreen() {
    for status in Self.absent + [.running, .reaching] {
      XCTAssertTrue(MenuModel.service(status: status).items.allSatisfy(\.isEnabled), "\(status)")
    }
  }

  func testTheServiceToggleOffersTheWayBackOnEveryAbsentScreen() {
    for status in Self.absent {
      XCTAssertEqual(MenuModel.service(status: status).items.map(\.title), ["Start Timer Service"], "\(status)")
    }
    XCTAssertEqual(MenuModel.service(status: .running).items.map(\.title), ["Stop Timer Service"])
    XCTAssertEqual(MenuModel.service(status: .reaching).items.map(\.title), ["Stop Timer Service"])
  }

  // MARK: Private

  private static let absent: [ServiceStatus] = [.stopped, .launchRefused, .notAnswering]

  private func modelWithATask() -> TaskWindowModel {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    return model
  }

  private func enabled(_ menu: MenuModel<TimerAction>) -> [TimerAction] {
    menu.items.filter(\.isEnabled).map(\.action)
  }

}

// MARK: - ServiceDownWindowTests

/// The window on each of the three screens: what it keeps, what it drops, and the sentence that
/// tells the three apart.
final class ServiceDownWindowTests: XCTestCase {

  // MARK: Internal

  /// throwntom-faa. A stop that survives a relaunch is safe only because the window says whose
  /// decision it was; without that it is a "why is nothing happening" with no way in.
  func testAStoppedServiceSaysTheUserStoppedItAndOffersTheWayBack() throws {
    let stopped = content(nil, connection: .stopped, status: .stopped)

    XCTAssertEqual(stopped.title, "Timer service stopped")
    XCTAssertEqual(stopped.serviceAction, .start)
    let notice = try XCTUnwrap(stopped.notice)
    XCTAssertTrue(notice.contains("You stopped"), notice)
  }

  /// The other half of "a choice is not a fault", asserted where it is actually decided: the
  /// window renders whatever error it is handed, so only the client can promise there is none.
  @MainActor
  func testAStoppedClientHasNoFaultToReport() {
    let client = DaemonClient(
      transport: UnreachableDaemonTransport(),
      registrar: RecordingRegistrar(),
      intents: MemoryServiceIntentStore(.stopped),
    )

    XCTAssertNil(client.unresolvedError)
  }

  /// throwntom-azp. The screen that used to read "Starting timer…" for ever.
  func testAnAcceptedLaunchThatNeverArrivesSaysSoRatherThanStarting() throws {
    let stalled = content(makeState(phase: .work), connection: .startingDaemon, status: .notAnswering)

    XCTAssertEqual(stalled.title, "Timer service isn’t answering")
    let notice = try XCTUnwrap(stalled.notice)
    XCTAssertTrue(notice.contains("accepted"), notice)
    XCTAssertEqual(stalled.serviceAction, .start)
  }

  func testAnAcceptedLaunchThatNeverArrivesDropsTheLiveStateLikeARefusalDoes() {
    let stalled = content(makeState(phase: .work, completedToday: 3), connection: .startingDaemon, status: .notAnswering)

    XCTAssertEqual(stalled.scheme, Palette.scheme(for: nil))
    XCTAssertEqual(stalled.pose, .disconnected)
    XCTAssertNil(stalled.countdown)
    XCTAssertNil(stalled.garden)
    XCTAssertEqual(stalled.chips, [], "the daemon these would dispatch to never arrived")
  }

  /// The three titles are what a reader tells the screens apart by, so no two may match.
  func testTheThreeAbsentScreensSayThreeDifferentThings() {
    let titles = Set([
      content(nil, connection: .stopped, status: .stopped).title,
      content(nil, connection: .startingDaemon, status: .launchRefused).title,
      content(nil, connection: .startingDaemon, status: .notAnswering).title,
      content(nil, connection: .connecting, status: .reaching).title,
    ])

    XCTAssertEqual(titles.count, 4)
  }

  func testAServiceStillBeingDialledCarriesNoExplanationOfItsOwn() {
    XCTAssertNil(content(nil, connection: .connecting, status: .reaching).notice)
    XCTAssertNil(content(makeState(phase: .work), status: .running).notice)
  }

  /// throwntom-7xn. A panel left open when the service went down would go on showing a stale list
  /// whose rows refuse, or open onto nothing at all.
  func testAPanelIsNotShownOnAnyScreenWithoutADaemon() {
    for status in [ServiceStatus.stopped, .launchRefused, .notAnswering] {
      XCTAssertNil(content(nil, connection: .stopped, status: status, panel: .tasks).panel, "\(status)")
      XCTAssertNil(content(nil, connection: .stopped, status: status, panel: .stats).panel, "\(status)")
    }
  }

  /// Presentation only: the window model still holds the panel, so it comes back with the daemon
  /// rather than needing to be reopened.
  func testAPanelSurvivesAReconnectBecauseTheWindowOnlyDeclinesToDrawIt() {
    XCTAssertEqual(content(makeState(phase: .work), status: .reaching, panel: .tasks).panel, .tasks)
    XCTAssertEqual(content(makeState(phase: .work), status: .running, panel: .stats).panel, .stats)
  }

  // MARK: Private

  private let now = Date(timeIntervalSince1970: 1_000_000)

  private func content(
    _ state: DaemonState?,
    connection: DaemonClient.Connection = .connected,
    status: ServiceStatus,
    panel: WindowPanel? = nil,
  ) -> MainWindowContent {
    MainWindowContent(
      state: state,
      connection: connection,
      status: status,
      tasks: TaskList(),
      error: nil,
      panel: panel,
      now: now,
    )
  }

}

// MARK: - ServiceDownNoteTests

/// Where the sentence lands. The fault note and the explanation are separate fields because they
/// are separate things: one reports something going wrong, the other explains a screen that is
/// working exactly as asked.
@MainActor
final class ServiceDownNoteTests: XCTestCase {

  func testBothNotesCanBeShownAtOnce() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    let notes = WindowNotes(error: "something broke", notice: "you stopped it", responder: environment.responder)

    _ = notes.body
  }

  /// The wiring the persisted stop rests on. `AppEnvironment` builds the client, so a store that
  /// never reached it would leave the ruling implemented and unused.
  func testTheEnvironmentHandsTheRecordedIntentToItsClient() throws {
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      intents: MemoryServiceIntentStore(.stopped),
    )

    XCTAssertEqual(environment.client.serviceStatus, .stopped)
  }

}

// MARK: - ServiceDownWiringTests

/// The gate reaching the surfaces, rather than the gate itself. Every other test in this file
/// hands `daemonAvailable:` to a menu model as a literal, which proves the model obeys it and
/// nothing about whether any view ever asks. Each of these drives a real `AppEnvironment` whose
/// only unusual property is a recorded stop, so a view that stopped consulting `serviceStatus`
/// fails here — which is the exact regression this branch exists to prevent, one surface at a time.
@MainActor
final class ServiceDownWiringTests: XCTestCase {

  // MARK: Internal

  func testTheMenuBarAsksTheClientWhetherThereIsADaemon() throws {
    let menus = AppMenus(environment: try stoppedEnvironment())

    XCTAssertFalse(menus.daemonAvailable)
    XCTAssertTrue(menus.timerMenu.items.allSatisfy { !$0.isEnabled }, "⌘⇧P and ⌘K would fire into nothing")
    XCTAssertEqual(menus.serviceMenu.items.map(\.title), ["Start Timer Service"])
  }

  func testTheCommandChipRowAsksTheClientWhetherThereIsADaemon() throws {
    let chips = CommandChips(environment: try stoppedEnvironment(), scheme: Palette.scheme(for: nil))

    XCTAssertFalse(try XCTUnwrap(chips.menu.item(for: .tasks)).isEnabled)
    XCTAssertFalse(try XCTUnwrap(chips.menu.item(for: .stats)).isEnabled)
    XCTAssertTrue(try XCTUnwrap(chips.menu.item(for: .shortcuts)).isEnabled, "the cheat sheet is local")
  }

  func testARowContextMenuAsksTheClientWhetherThereIsADaemon() throws {
    let menu = TaskContextMenu(task: makeTask(id: 1), environment: try stoppedEnvironment()).menu

    XCTAssertFalse(menu.items.isEmpty)
    XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
  }

  func testTheWindowAsksTheClientWhetherThereIsADaemon() throws {
    let environment = try stoppedEnvironment()
    environment.windowModel.panel = .tasks

    let content = MainWindow(environment: environment).windowContent

    XCTAssertEqual(content.title, "Timer service stopped")
    XCTAssertEqual(content.chips, [])
    XCTAssertEqual(content.serviceAction, .start)
    XCTAssertNil(content.panel, "a panel left open when the service went down draws nothing")
    XCTAssertNotNil(content.notice)
  }

  /// The same window with a daemon, so the assertions above are about the stop and not about
  /// `AppEnvironment` simply producing an empty window whatever it is told.
  func testTheSameWindowWithADaemonKeepsEverything() async throws {
    let environment = AppEnvironment(transport: try StubTransport(states: [makeState(phase: .work)]))
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil }
    environment.windowModel.panel = .tasks

    let content = MainWindow(environment: environment).windowContent

    XCTAssertEqual(content.title, "Pomodoro")
    XCTAssertFalse(content.chips.isEmpty)
    XCTAssertEqual(content.serviceAction, .stop)
    XCTAssertEqual(content.panel, .tasks)
    XCTAssertNil(content.notice)
  }

  // MARK: Private

  /// An app whose recorded intent is a stop, which is the one launch that reaches the stopped
  /// screen without any dialling having to fail first.
  private func stoppedEnvironment() throws -> AppEnvironment {
    AppEnvironment(transport: try StubTransport(states: []), intents: MemoryServiceIntentStore(.stopped))
  }

}

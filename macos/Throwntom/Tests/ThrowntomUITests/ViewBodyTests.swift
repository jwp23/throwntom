import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// Builds every view and scene body in each state the app can be in. What a SwiftUI body decides
/// is asserted against `MenuModel` and `MainWindowContent`; what is left here is that the bodies
/// themselves build without trapping, which is the part no plain unit test can reach.
@MainActor
final class ViewBodyTests: XCTestCase {

  // MARK: Internal

  func testBodiesBuildBeforeTheDaemonAnswers() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))

    buildEveryBody(of: environment)
  }

  func testBodiesBuildWithTasksAndAConfirmationPending() async throws {
    let tasks = TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: [makeTask(id: 3, done: true)])
    let state = makeState(
      phase: .awaitingConfirm,
      nextStage: DaemonState.NextStage(state: .shortBreak, duration: 300),
      focusedTaskIds: [1],
    )
    let environment = AppEnvironment(transport: try StubTransport(states: [state], tasks: tasks))
    defer { shutDown(environment) }
    environment.start()
    try await waitUntil { environment.client.tasks.active.map(\.id) == [1, 2] }
    environment.model.sync(tasks: environment.client.tasks, focusedTaskIDs: [1])

    buildEveryBody(of: environment)
  }

  func testBodiesBuildWhileTheDaemonIsUnreachable() async throws {
    let environment = AppEnvironment(transport: UnreachableDaemonTransport())
    defer { shutDown(environment) }
    environment.start()
    // lastError, not unresolvedError: a client that has never connected shows the status line
    // alone, so the outage is recorded without a note under it.
    try await waitUntil { environment.client.lastError != nil }

    buildEveryBody(of: environment)
  }

  func testBodiesBuildWhileMacOSRefusesToDeliverReminders() async throws {
    let environment = AppEnvironment(
      transport: try StubTransport(states: []),
      authorizer: StubAuthorizer(refusal: notificationsNotAllowed),
    )
    await environment.responder.requestAuthorization()
    XCTAssertNotNil(environment.responder.authorization.problem)

    buildEveryBody(of: environment)
  }

  func testBodiesBuildWhileTheInlineEditorIsOpen() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    environment.model.beginNewTask()

    buildEveryBody(of: environment)
  }

  // MARK: Private

  private func buildEveryBody(of environment: AppEnvironment) {
    _ = ThrowntomScenes(environment: environment).body
    _ = AppMenus(environment: environment).body
    _ = MainWindow(environment: environment).body
    environment.windowModel.panel = .tasks
    _ = MainWindow(environment: environment).body
    environment.windowModel.panel = .stats
    _ = MainWindow(environment: environment).body
    _ = NewTaskRow(model: environment.model) { _ in }.body
    _ = TaskRow(task: makeTask(id: 1), focused: true).body
    _ = TaskRow(task: makeTask(id: 2, done: true), focused: false).body
    _ = LoginItemToggle(registrar: environment.registrar).body
    _ = ShortcutSheet(environment: environment).body
  }

  private func shutDown(_ environment: AppEnvironment) {
    environment.client.stop()
    environment.ticker.stop()
  }

}

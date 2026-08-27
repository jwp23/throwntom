import SwiftUI
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// Builds every view and scene body in each state the app can be in. What a SwiftUI body decides
/// is asserted against `MenuModel` and `TaskWindowContent`; what is left here is that the bodies
/// themselves build without trapping, which is the part no plain unit test can reach.
@MainActor
final class ViewBodyTests: XCTestCase {
    func testBodiesBuildBeforeTheDaemonAnswers() throws {
        let environment = AppEnvironment(transport: try StubTransport(states: []))

        buildEveryBody(of: environment)
    }

    func testBodiesBuildWithTasksAndAConfirmationPending() async throws {
        let environment = AppEnvironment(
            transport: try StubTransport(states: [makeState(phase: .awaitingConfirm, focusedTaskIds: [1])]))
        defer { shutDown(environment) }
        environment.start()
        try await waitUntil { environment.client.connection == .connected }
        environment.model.sync(
            tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: [makeTask(id: 3, done: true)]),
            focusedTaskIDs: [1])

        buildEveryBody(of: environment)
    }

    func testBodiesBuildWhileTheInlineEditorIsOpen() throws {
        let environment = AppEnvironment(transport: try StubTransport(states: []))
        environment.model.beginNewTask()

        buildEveryBody(of: environment)
    }

    private func buildEveryBody(of environment: AppEnvironment) {
        _ = ThrowntomScenes(environment: environment).body
        _ = AppMenus(client: environment.client, model: environment.model).body
        _ = TaskWindow(client: environment.client, model: environment.model).body
        _ = PopoverView(client: environment.client, ticker: environment.ticker, registrar: environment.registrar).body
        _ = NewTaskRow(model: environment.model) { _ in }.body
        _ = TimerActionButton(action: .start, client: environment.client).body
        _ = TimerActionButton(action: .skipToday, client: environment.client).body
        _ = TaskRow(task: makeTask(id: 1), focused: true).body
        _ = TaskRow(task: makeTask(id: 2, done: true), focused: false).body
    }

    private func shutDown(_ environment: AppEnvironment) {
        environment.client.stop()
        environment.ticker.stop()
    }
}

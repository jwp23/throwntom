import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class MainWindowSyncTests: XCTestCase {
  func testWindowCopiesDaemonTasksAndFocusIntoTheModel() async throws {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5)], completed: [makeTask(id: 6, done: true)])
    let environment = AppEnvironment(transport: try StubTransport(
      states: [makeState(phase: .work, focusedTaskIds: [5])],
      tasks: tasks,
    ))
    defer { environment.client.stop() }
    environment.start()
    try await waitUntil { environment.client.state != nil && !environment.client.tasks.active.isEmpty }
    MainWindow(environment: environment).syncModel()
    XCTAssertEqual(environment.model.tasks.active.map(\.id), [4, 5])
    XCTAssertEqual(environment.model.tasks.completed.map(\.id), [6])
    XCTAssertEqual(environment.model.focusedIDs, [5])
  }

  func testEscapeClosesThePanelBeforeCancellingAnEdit() throws {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    environment.windowModel.panel = .tasks
    environment.model.beginNewTask()
    MainWindow(environment: environment).escape()
    XCTAssertNil(environment.windowModel.panel)
    XCTAssertTrue(environment.model.isEditing)
    MainWindow(environment: environment).escape()
    XCTAssertFalse(environment.model.isEditing)
  }

  /// A default-priority announcement is dropped when VoiceOver is already speaking. These are the
  /// lines that must not be dropped: the window has just lost its timer, and the reader has no
  /// other signal. High priority interrupts instead, which is the right trade for an event this
  /// rare and this consequential — `ServiceAnnouncer` is what keeps it rare.
  func testTheSpokenLineInterruptsRatherThanQueueingBehindWhateverIsBeingRead() {
    let spoken = SpokenLine.attributed("Timer service stopped.")

    XCTAssertEqual(spoken.accessibilitySpeechAnnouncementPriority, .high)
    XCTAssertEqual(String(spoken.characters), "Timer service stopped.")
  }
}

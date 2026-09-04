import AppKit
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class TasksPanelTests: XCTestCase {

  // MARK: Internal

  /// A finished task differs from an outstanding one by a line through it and nothing else, and a
  /// line through text is silent. Found while auditing the window for what it says only in ink;
  /// no bead covered it.
  func testARowSaysInWordsWhatItOtherwiseOnlyDraws() {
    XCTAssertEqual(TaskRow(task: makeTask(id: 1, description: "write"), focused: false).label, "write")
    XCTAssertEqual(TaskRow(task: makeTask(id: 2, description: "write"), focused: true).label, "write, focused")
    XCTAssertEqual(
      TaskRow(task: makeTask(id: 3, description: "write", done: true), focused: false).label,
      "write, completed",
    )
  }

  func testEmptyStateNamesTheShortcutThatAddsATask() {
    XCTAssertEqual(TaskHints.empty, "No tasks — ⌘N to add one")
  }

  func testPlaceholderStandsInForAnEmptyList() throws {
    let panel = try makePanel()

    XCTAssertTrue(panel.showsEmptyState, "nothing to list yet")

    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    XCTAssertFalse(panel.showsEmptyState)

    panel.model.sync(tasks: TaskList(active: [], completed: [makeTask(id: 2, done: true)]), focusedTaskIDs: [])
    XCTAssertFalse(panel.showsEmptyState, "a completed task is still a task")
  }

  func testOpeningTheEditorReplacesThePlaceholderWithTheRow() throws {
    let panel = try makePanel()
    panel.model.beginNewTask()

    XCTAssertFalse(panel.showsEmptyState)
  }

  func testPanelBodyBuildsEmptyAndPopulated() throws {
    let panel = try makePanel()
    _ = panel.body
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: [makeTask(id: 2, done: true)]), focusedTaskIDs: [1])
    _ = panel.body
  }

  /// A row inserted above the current top row left the list scrolled to where it was before the
  /// insertion, clipping the top of whatever row that scroll position now landed on — the bug
  /// UAT saw as the first task half-hidden under the header. `NewTaskRow` opening above the
  /// existing tasks is the concrete trigger: reproduce it by hosting the real AppKit-backed list
  /// (`List` doesn't render through `ImageRenderer`, so this measures the scroll clip view's
  /// bounds directly rather than rendering a comparable image) and asserting the visible area
  /// still starts at the list's true top once the editor row opens.
  func testOpeningTheEditorLeavesTheListScrolledToTheTop() throws {
    let panel = try makePanel()
    panel.model.sync(
      tasks: TaskList(active: [makeTask(id: 1, description: "first"), makeTask(id: 2, description: "second")], completed: []),
      focusedTaskIDs: [],
    )
    let hosting = NSHostingView(rootView: panel.frame(width: 300))
    hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
    let window = NSWindow(
      contentRect: hosting.frame,
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false,
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()

    panel.model.beginNewTask()
    hosting.rootView = panel.frame(width: 300)
    hosting.layoutSubtreeIfNeeded()

    let clipView = try XCTUnwrap(Self.findScrollClipView(in: hosting), "no scroll clip view found under the tasks list")
    XCTAssertEqual(clipView.bounds.origin.y, 0, "the editor row must not open scrolled out from under the header")
  }

  // MARK: Private

  /// Walks the AppKit view tree `List` builds to find its scroll clip view. Matched by class-name
  /// substring rather than the private SwiftUI type itself, since that type is not public API.
  private static func findScrollClipView(in view: NSView) -> NSView? {
    if "\(type(of: view))".contains("ClipView") {
      return view
    }
    for subview in view.subviews {
      if let found = findScrollClipView(in: subview) {
        return found
      }
    }
    return nil
  }

  private func makePanel() throws -> TasksPanel {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return TasksPanel(environment: environment, scheme: Palette.scheme(for: .work))
  }

}

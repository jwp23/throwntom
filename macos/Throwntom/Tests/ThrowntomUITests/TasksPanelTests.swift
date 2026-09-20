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
    XCTAssertEqual(makeRow(id: 1, description: "write", focused: false).label, "write")
    XCTAssertEqual(makeRow(id: 2, description: "write", focused: true).label, "write, focused")
    XCTAssertEqual(makeRow(id: 3, description: "write", done: true, focused: false).label, "write, completed")
  }

  /// The panel's hint is the one place a reader who has never opened a context menu learns that
  /// ⌘⇧F is a toggle, so it has to word itself for the row the key would act on.
  func testTheHintNamesUnfocusWhenTheSelectedRowIsFocused() throws {
    let panel = try makePanel()
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1), makeTask(id: 2)], completed: []), focusedTaskIDs: [2])

    panel.model.selectedID = 1
    XCTAssertEqual(panel.hintLine, TaskHints.line(focused: false))

    panel.model.selectedID = 2
    XCTAssertEqual(panel.hintLine, TaskHints.line(focused: true))
  }

  /// The rows sit on the panel, so their star takes the panel's text colour rather than a tint of
  /// its own; `PaletteTests` is what holds that colour to 4.5:1.
  func testTheRowMarkTakesThePanelsOwnTextColour() throws {
    let scheme = Palette.scheme(for: .idle)
    let panel = TasksPanel(environment: AppEnvironment(transport: try StubTransport(states: [])), scheme: scheme)
    XCTAssertEqual(panel.markColor, scheme.panelTaskMark)
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

  /// Submitting the inline editor while it is hosted for real hands the line to the daemon
  /// through `DaemonDispatch.send`, exactly as `taskList` wires it — reached through the real
  /// AppKit text field `List` builds, not a copy of the closure. TasksPanel.swift:75:11/75:46.
  func testSubmittingTheNewTaskRowSendsItToTheDaemon() async throws {
    let transport = try StubTransport(states: [])
    let environment = AppEnvironment(transport: transport)
    let panel = TasksPanel(environment: environment, scheme: Palette.scheme(for: .work))
    panel.model.beginNewTask()
    panel.model.draft = "buy milk"
    let (hosting, _) = Self.host(panel)

    let field = try XCTUnwrap(
      findTextField(in: hosting),
      "no text field found for the inline new-task row",
    )
    _ = field.sendAction(field.action, to: field.target)

    try await waitUntil { !transport.commands.isEmpty }
    XCTAssertEqual(transport.commands.first?.body, #"{"line":"task add buy milk"}"#)
    XCTAssertFalse(panel.model.isEditing, "the row closes once its draft is sent")
  }

  /// Every statement `body` builds, spelled out as the type SwiftUI actually composed: the
  /// header, the placeholder/list-and-hint pair `_ConditionalContent` encodes for *both*
  /// branches at once regardless of which one runs, and inside the list the new-task row, the
  /// active `ForEach` with each row's tag and its context menu's `TaskContextMenu`, and the
  /// completed section's `DisclosureGroup` with its own `ForEach` of `TaskRow`. A statement that
  /// stops being built — anywhere in this tree — changes this string, whether or not the branch
  /// it lives in happens to run for this panel's data.
  func testBodyIsBuiltFromTheHeaderPlaceholderListAndHint() throws {
    let panel = try makePanel()

    XCTAssertEqual(
      shape(of: panel.body),
      "ModifiedContent<ModifiedContent<ModifiedContent<VStack<TupleView<(ModifiedContent<Text, "
        + "_EnvironmentKeyWritingModifier<Optional<Text.Case>>>, _ConditionalContent<ModifiedContent<Text, "
        + "_FlexFrameLayout>, TupleView<(ScrollViewReader<ModifiedContent<ModifiedContent<ModifiedContent<"
        + "ModifiedContent<ModifiedContent<List<Int, TupleView<(Optional<IDView<NewTaskRow, Int>>, "
        + "ForEach<Array<TaskItem>, Int, ModifiedContent<ModifiedContent<ModifiedContent<TaskRow, "
        + "_TraitWritingModifier<TagValueTraitKey<Int>>>, _TraitWritingModifier<TagValueTraitKey<Optional<Int>>>>, "
        + "ContextMenuModifier<ZStack<ModifiedContent<TaskContextMenu, StyleContextWriter<MenuStyleContext>>>>>>, "
        + "Optional<DisclosureGroup<Text, ForEach<Array<TaskItem>, Int, TaskRow>>>)>>, "
        + "ListStyleWriter<PlainListStyle>>, ScrollContentBackgroundModifier>, _FlexFrameLayout>, "
        + "_ValueActionModifier2<Optional<Int>>>, _AppearanceActionModifier>>, ShortcutHint)>>)>>, "
        + "_PaddingLayout>, _ForegroundStyleModifier<Color>>, "
        + "_InsettableBackgroundShapeModifier<Color, RoundedRectangle>>",
    )
  }

  /// The completed section opens collapsed: a panel with completed tasks shows only their
  /// disclosure header until it is clicked, never the rows underneath. TasksPanel.swift:61:38.
  func testTheCompletedSectionStartsCollapsed() throws {
    let panel = try makePanel()
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    let rowsWithNoCompletedSection = Self.countTableRows(in: Self.host(panel).view)

    panel.model.sync(
      tasks: TaskList(active: [makeTask(id: 1)], completed: [makeTask(id: 2, done: true)]),
      focusedTaskIDs: [],
    )
    let (view, _) = Self.host(panel)
    // `DisclosureGroup` settles onto its bound `isExpanded` value one runloop turn after the
    // outline view's own initial paint, which starts collapsed regardless of that value.
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    view.layoutSubtreeIfNeeded()
    let rowsBeforeExpanding = Self.countTableRows(in: view)

    XCTAssertEqual(
      rowsBeforeExpanding,
      rowsWithNoCompletedSection + 1,
      "only the collapsed header adds a row; the completed task's own row is not built yet",
    )
  }

  /// The completed section is a row of its own — the collapsed `DisclosureGroup` — and it is
  /// there only once there is a completed task to disclose. TasksPanel.swift:83:12.
  func testTheCompletedSectionIsRenderedOnlyWhenThereIsSomethingCompleted() throws {
    let panel = try makePanel()
    panel.model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])
    let withoutCompleted = Self.countTableRows(in: Self.host(panel).view)

    panel.model.sync(
      tasks: TaskList(active: [makeTask(id: 1)], completed: [makeTask(id: 2, done: true)]),
      focusedTaskIDs: [],
    )
    let withCompleted = Self.countTableRows(in: Self.host(panel).view)

    XCTAssertEqual(
      withCompleted,
      withoutCompleted + 1,
      "one extra row appears: the collapsed completed-tasks disclosure group",
    )
  }

  /// The completed section always draws its rows unfocused, no matter which task is actually
  /// focused: the row's mark is compared, pixel for pixel, against a genuinely-focused and a
  /// genuinely-unfocused row that otherwise read identically. TasksPanel.swift:86:44.
  func testACompletedRowIsDrawnUnfocusedEvenWhenItsTaskIsTheFocusedOne() throws {
    let panel = try makePanel()
    // Same description and strikethrough on every row, so only the focus mark can make their
    // pixels differ. `done: true` on the active rows matches the completed row's strikethrough
    // without changing which section — active or completed — draws each one.
    panel.model.sync(
      tasks: TaskList(
        active: [
          makeTask(id: 1, description: "match", done: true),
          makeTask(id: 2, description: "match", done: true),
        ],
        completed: [makeTask(id: 3, description: "match", done: true)],
      ),
      focusedTaskIDs: [1, 3],
    )
    let (hosting, _) = Self.host(panel)
    guard let disclosure = Self.findDisclosureButton(in: hosting) else {
      return XCTFail("no disclosure button found to expand the completed section")
    }
    _ = disclosure.sendAction(disclosure.action, to: disclosure.target)
    hosting.layoutSubtreeIfNeeded()

    let cells = Self.findCellHostingViews(in: hosting)
    // [0] the focused active row, [1] the unfocused active row, [2] the disclosure group's own
    // header label, [3] the completed row now that expanding it has built its content.
    guard cells.count >= 4 else {
      return XCTFail("expected a focused row, an unfocused row, a header and the completed row; found \(cells.count) cells")
    }
    let focusedActiveRow = try Self.snapshot(cells[0])
    let unfocusedActiveRow = try Self.snapshot(cells[1])
    let completedRow = try Self.snapshot(cells[3])

    XCTAssertNotEqual(focusedActiveRow, unfocusedActiveRow, "the two reference rows must actually differ by focus")
    XCTAssertEqual(completedRow, unfocusedActiveRow, "a completed row must be drawn unfocused")
    XCTAssertNotEqual(completedRow, focusedActiveRow, "a completed row must not be drawn as the focused one")
  }

  // MARK: Private

  /// Hosts a fresh copy of the panel's current state in a real AppKit window and lays it out, so
  /// `List` actually builds the rows its content closures describe.
  private static func host(_ panel: TasksPanel) -> (view: NSHostingView<some View>, window: NSWindow) {
    hostInWindow(panel.frame(width: 300))
  }

  private static func countTableRows(in view: NSView) -> Int {
    let own = "\(type(of: view))".contains("ListTableRowView") ? 1 : 0
    return own + view.subviews.reduce(0) { $0 + countTableRows(in: $1) }
  }

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

  /// Every row's own drawing surface, in the order `List` lays them out — top to bottom, the
  /// same order the source builds them in.
  private static func findCellHostingViews(in view: NSView) -> [NSView] {
    var found = [NSView]()
    if "\(type(of: view))".contains("CellHostingView") {
      found.append(view)
    }
    for subview in view.subviews {
      found += findCellHostingViews(in: subview)
    }
    return found
  }

  /// What a row actually drew, as PNG bytes: the only way to tell a hardcoded focus mark from
  /// the real one, since `List` bridges each row to AppKit and does not keep the SwiftUI value
  /// that built it.
  private static func snapshot(_ view: NSView) throws -> Data {
    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }

  /// The completed section's disclosure triangle: the control that expands it, so a test can
  /// drive that the same way a click would.
  private static func findDisclosureButton(in view: NSView) -> NSButton? {
    if let button = view as? NSButton, button.action == Selector(("_outlineControlClicked:")) {
      return button
    }
    for subview in view.subviews {
      if let found = findDisclosureButton(in: subview) {
        return found
      }
    }
    return nil
  }

  private func makeRow(id: Int, description: String = "task", done: Bool = false, focused: Bool) -> TaskRow {
    TaskRow(
      task: makeTask(id: id, description: description, done: done),
      focused: focused,
      markColor: Palette.scheme(for: .work).panelTaskMark,
    )
  }

  private func makePanel() throws -> TasksPanel {
    let environment = AppEnvironment(transport: try StubTransport(states: []))
    return TasksPanel(environment: environment, scheme: Palette.scheme(for: .work))
  }

}

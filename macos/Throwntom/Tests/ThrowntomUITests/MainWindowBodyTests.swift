import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - MainWindowBodyTests

/// What the window is actually made of, read back out of `MainWindow.body`.
///
/// SwiftUI cannot render a window in a test process, but it does not have to: everything the body
/// built is still in the value it returned. The stacked sections are the generic parameters of the
/// `VStack`'s `TupleView`, so a section that stops being built changes the type. An `if` without an
/// `else` leaves an `Optional` whose type names the view either way, so the type says what would be
/// drawn and the value says whether it is being drawn now. And each modifier hangs off the stack as
/// a value, so the closures behind Escape, the sheet and the five `onChange` watchers can be called
/// directly — driving exactly what the running window drives.
///
/// The decisions these sections draw from live in `MainWindowContent` and are tested there; what is
/// pinned here is the window that reads them.
@MainActor
final class MainWindowBodyTests: XCTestCase {

  // MARK: Internal

  func testTheWindowStacksTheHeaderGardenChipsFieldsNotesFocusAndPanels() throws {
    XCTAssertEqual(try sections(of: try makeEnvironment()).map(shape), [
      "TimerHeader",
      "Optional<TomatoGardenView>",
      "ActionChips",
      "Optional<SnoozeEntryRow>",
      "Optional<MeetingEntryRow>",
      "Optional<LunchEntryRow>",
      "ModifiedContent<ServiceChip, _PaddingLayout>",
      "CommandChips",
      "WindowNotes",
      "FocusSection",
      "Optional<TasksPanel>",
      "Optional<StatsPanel>",
    ])
  }

  /// What the window hangs off that stack, in the order the body applies it: the margin and the
  /// frame, the phase colours, the two animations, and then the wiring — Escape, the cheat sheet,
  /// the three chip watchers that withdraw a length field, and the two that copy the daemon's
  /// tasks into the model. Each `.onChange` takes two places: the change action, and an appearance
  /// action SwiftUI fills in only when `initial` is true.
  ///
  /// Named by SwiftUI's own types, which is what makes the list readable as the window it
  /// describes; if a macOS release renames one this fails loudly rather than stopping checking.
  func testTheWindowIsPaddedColouredAnimatedAndWired() throws {
    XCTAssertEqual(try modifiers(of: try makeEnvironment()).map(shape), [
      "_PaddingLayout",
      "_FlexFrameLayout",
      "_BackgroundStyleModifier<Color>",
      "_BackgroundModifier<WindowElevator>",
      "_ForegroundStyleModifier<Color>",
      "_AnimationModifier<PhaseScheme>",
      "_AnimationModifier<Optional<WindowPanel>>",
      "OnCommandModifier",
      "SheetPresentationModifier<ShortcutSheet, NullSheetAnchor<SheetPreference.Key>>",
      "_ValueActionModifier2<Bool>",
      "_AppearanceActionModifier",
      "_ValueActionModifier2<Bool>",
      "_AppearanceActionModifier",
      "_ValueActionModifier2<Bool>",
      "_AppearanceActionModifier",
      "_ValueActionModifier2<TaskList>",
      "_AppearanceActionModifier",
      "_ValueActionModifier2<Optional<Array<Int>>>",
      "_AppearanceActionModifier",
      "_TaskModifier",
    ])
  }

  /// `minimumContentWidth` is what `TimerHeaderTests` measures the title against, and nothing in
  /// the window reads it — so on its own it is a number free to drift away from the window it
  /// claims to describe. Here it is held to the frame and the margin the body actually asks for.
  func testTheNarrowestTextColumnIsTheWindowInsideItsMargins() throws {
    let layers = try modifiers(of: try makeEnvironment())
    let margin = try XCTUnwrap(try child("insets", of: try part(Layer.padding.rawValue, of: layers)) as? EdgeInsets)
    let narrowest = try XCTUnwrap(try child("minWidth", of: try part(Layer.frame.rawValue, of: layers)) as? CGFloat)

    XCTAssertEqual(MainWindow.minimumContentWidth, narrowest - margin.leading - margin.trailing)
  }

  /// The three length fields share one place under the chips, and only the one being typed into is
  /// drawn — the rule `WindowModel.beginEntry` enforces, seen from the window.
  func testALengthFieldIsDrawnOnlyWhileThatLengthIsBeingTyped() throws {
    let environment = try makeEnvironment()
    let fields: [Section] = [.snoozeField, .meetingField, .lunchField]

    XCTAssertEqual(try drawn(fields, in: environment), [], "no field is open on launch")
    environment.windowModel.beginEntry(.snooze)
    XCTAssertEqual(try drawn(fields, in: environment), ["SnoozeEntryRow"])
    environment.windowModel.beginEntry(.meeting)
    XCTAssertEqual(try drawn(fields, in: environment), ["MeetingEntryRow"])
    environment.windowModel.beginEntry(.lunch)
    XCTAssertEqual(try drawn(fields, in: environment), ["LunchEntryRow"])
  }

  func testThePanelUnderTheWindowIsTheOneTheUserOpened() throws {
    let environment = try makeEnvironment()
    let panels: [Section] = [.tasksPanel, .statsPanel]

    XCTAssertEqual(try drawn(panels, in: environment), [], "panels start closed on every launch")
    environment.windowModel.panel = .tasks
    XCTAssertEqual(try drawn(panels, in: environment), ["TasksPanel"])
    environment.windowModel.panel = .stats
    XCTAssertEqual(try drawn(panels, in: environment), ["StatsPanel"])
  }

  /// Escape reaches the window as macOS's Cancel command, and what the window answers it with is
  /// `escape()`. What `escape()` then decides is `MainWindowSyncTests`' business; what is pinned
  /// here is that pressing Escape runs it at all.
  func testTheWindowAnswersCancelByEscaping() throws {
    let environment = try makeEnvironment()
    environment.windowModel.panel = .tasks
    let exit = try modifier(.exitCommand, of: environment)
    XCTAssertEqual(String(describing: try child("command", of: exit)), "cancelOperation:")
    let cancel = try XCTUnwrap(
      try child("action", of: try child("action", of: exit)) as? () -> Void,
      "the Cancel command has nothing to run",
    )

    cancel()

    XCTAssertNil(environment.windowModel.panel, "Escape closed the panel that was open")
  }

  func testTheWindowPresentsTheCheatSheetForItsOwnApp() throws {
    let environment = try makeEnvironment()
    let sheet = try modifier(.sheet, of: environment)
    let build = try XCTUnwrap(
      try child("sheetContent", of: sheet) as? () -> ShortcutSheet,
      "the window presents \(shape(of: sheet)), which is not a cheat sheet",
    )

    XCTAssertTrue(build().environment === environment, "the sheet reads the window's own app")
  }

  func testAWithdrawnSnoozeChipClosesTheDurationFieldBehindIt() throws {
    try assertTheFieldFollowsItsChip("snooze", watchedBy: .snoozeChipChange)
  }

  func testAWithdrawnMeetingChipClosesTheLengthFieldBehindIt() throws {
    try assertTheFieldFollowsItsChip("meeting", watchedBy: .meetingChipChange)
  }

  func testAWithdrawnLunchChipClosesTheLengthFieldBehindIt() throws {
    try assertTheFieldFollowsItsChip("lunch", watchedBy: .lunchChipChange)
  }

  func testTheWindowCopiesANewTaskListIntoTheModel() async throws {
    let environment = try await makeBusyEnvironment()
    defer { shutDown(environment) }
    let listChanged = try XCTUnwrap(
      try child("action", of: try modifier(.taskListChange, of: environment)) as? (TaskList, TaskList) -> Void,
      "the task-list watcher does not take a pair of task lists",
    )
    XCTAssertEqual(environment.model.tasks.active.map(\.id), [], "nothing has been copied yet")

    listChanged(TaskList(), environment.client.tasks)

    XCTAssertEqual(environment.model.tasks.active.map(\.id), [4, 5])
    XCTAssertEqual(environment.model.tasks.completed.map(\.id), [6])
  }

  func testTheWindowCopiesNewFocusIntoTheModel() async throws {
    let environment = try await makeBusyEnvironment()
    defer { shutDown(environment) }
    let focusChanged = try XCTUnwrap(
      try child("action", of: try modifier(.focusChange, of: environment)) as? ([Int]?, [Int]?) -> Void,
      "the focus watcher does not take a pair of task-id lists",
    )
    XCTAssertEqual(environment.model.focusedIDs, [], "nothing has been copied yet")

    focusChanged(nil, [5])

    XCTAssertEqual(environment.model.focusedIDs, [5])
  }

  /// Both task watchers run for the value they start with, not only for the next change. Without
  /// that, a window opened onto a daemon that has been settled for hours lists no tasks and stars
  /// nothing until something moves.
  func testTheWindowSyncsTheModelAsSoonAsItAppears() async throws {
    let environment = try await makeBusyEnvironment()
    defer { shutDown(environment) }
    let syncTasks = try XCTUnwrap(
      try child("appear", of: try modifier(.taskListAppear, of: environment)) as? () -> Void,
      "the task-list watcher is never run for the list it starts with",
    )
    XCTAssertNotNil(
      try child("appear", of: try modifier(.focusAppear, of: environment)) as? () -> Void,
      "the focus watcher is never run for the focus it starts with",
    )

    syncTasks()

    XCTAssertEqual(environment.model.tasks.active.map(\.id), [4, 5])
    XCTAssertEqual(environment.model.focusedIDs, [5])
  }

  // MARK: Private

  /// Where each section sits in the stack the body builds.
  private enum Section: Int {
    case header
    case garden
    case chips
    case snoozeField
    case meetingField
    case lunchField
    case service
    case commands
    case notes
    case focus
    case tasksPanel
    case statsPanel
  }

  /// Where each modifier sits in the stack the body hangs off the `VStack`, counted from the
  /// innermost. `testTheWindowIsPaddedColouredAnimatedAndWired` is what holds these to the source.
  private enum Layer: Int {
    case padding
    case frame
    case ground
    case elevation
    case text
    case schemeAnimation
    case panelAnimation
    case exitCommand
    case sheet
    case snoozeChipChange
    case snoozeChipAppear
    case meetingChipChange
    case meetingChipAppear
    case lunchChipChange
    case lunchChipAppear
    case taskListChange
    case taskListAppear
    case focusChange
    case focusAppear
    case authorization
  }

  private var everyField: [String] {
    ["snooze", "meeting", "lunch"]
  }

  /// A length field is closed by its own chip leaving the row, and by nothing else: not by that
  /// chip arriving, and not when the field was never open.
  ///
  /// All three fields are opened at once here, which `beginEntry` never does — it is how the
  /// watcher is asked about fields it is not responsible for, and answering for one of those would
  /// close a field the user is typing into.
  private func assertTheFieldFollowsItsChip(
    _ field: String,
    watchedBy layer: Layer,
    file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let environment = try makeEnvironment()
    let model = environment.windowModel
    let chipChanged = try XCTUnwrap(
      try child("action", of: try modifier(layer, of: environment)) as? (Bool, Bool) -> Void,
      "the watcher at \(layer) is not asked about a chip",
      file: file,
      line: line,
    )

    setEveryField(of: model, open: true)
    chipChanged(true, false)
    XCTAssertEqual(
      openFields(of: model),
      everyField.filter { $0 != field },
      "the \(field) field goes with the chip that answers it, and takes no other field with it",
      file: file,
      line: line,
    )

    setEveryField(of: model, open: true)
    chipChanged(false, true)
    XCTAssertEqual(openFields(of: model), everyField, "a chip arriving closes nothing", file: file, line: line)

    setEveryField(of: model, open: false)
    chipChanged(true, false)
    XCTAssertEqual(
      openFields(of: model),
      [],
      "a field nobody opened is not opened by its chip leaving",
      file: file,
      line: line,
    )
  }

  private func makeEnvironment() throws -> AppEnvironment {
    AppEnvironment(transport: try StubTransport(states: []))
  }

  /// A window over a daemon that has already published a working phase, two tasks and a focused
  /// one — the settled state the task watchers have something to copy from.
  private func makeBusyEnvironment() async throws -> AppEnvironment {
    let tasks = TaskList(active: [makeTask(id: 4), makeTask(id: 5)], completed: [makeTask(id: 6, done: true)])
    let environment = AppEnvironment(transport: try StubTransport(
      states: [makeState(phase: .work, focusedTaskIds: [5])],
      tasks: tasks,
    ))
    environment.start()
    try await waitUntil { environment.client.state != nil && !environment.client.tasks.active.isEmpty }
    return environment
  }

  private func shutDown(_ environment: AppEnvironment) {
    environment.client.stop()
    environment.ticker.stop()
  }

  private func sections(of environment: AppEnvironment) throws -> [Any] {
    try tupleParts(of: try stackContent(of: try unwrapped(MainWindow(environment: environment).body)))
  }

  private func modifiers(of environment: AppEnvironment) throws -> [Any] {
    modifierLayers(of: MainWindow(environment: environment).body)
  }

  private func modifier(_ layer: Layer, of environment: AppEnvironment) throws -> Any {
    try part(layer.rawValue, of: try modifiers(of: environment))
  }

  /// Which of the window's optional sections were actually built, named by what they draw.
  private func drawn(_ wanted: [Section], in environment: AppEnvironment) throws -> [String] {
    let stacked = try sections(of: environment)
    var built = [String]()
    for section in wanted {
      let slot = try part(section.rawValue, of: stacked)
      if isBuilt(slot) {
        built.append(shape(of: try child("some", of: slot)))
      }
    }
    return built
  }

  private func setEveryField(of model: WindowModel, open: Bool) {
    model.isEnteringSnooze = open
    model.isEnteringMeeting = open
    model.isEnteringLunch = open
  }

  private func openFields(of model: WindowModel) -> [String] {
    var open = [String]()
    if model.isEnteringSnooze {
      open.append("snooze")
    }
    if model.isEnteringMeeting {
      open.append("meeting")
    }
    if model.isEnteringLunch {
      open.append("lunch")
    }
    return open
  }

}

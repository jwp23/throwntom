import AppKit
import Foundation
import SwiftUI
import UserNotifications
import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

// MARK: - TimeoutError

struct TimeoutError: Error { }

// MARK: - UnexpectedShapeError

/// Thrown after `XCTFail` has already recorded why, to abort a helper that cannot go on — the
/// `XCTFail` message is the real reason; this only stops execution once it's been read.
struct UnexpectedShapeError: Error { }

extension MenuModel {
  func item(for action: Action) -> MenuItem<Action>? {
    items.first { $0.action == action }
  }
}

/// Polls `condition` every 20 ms until it holds or `timeout` seconds pass.
/// MainActor-isolated so tests can read DaemonClient's MainActor properties inside `condition`.
@MainActor
func waitUntil(timeout: Double = 5, _ condition: () -> Bool) async throws {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() {
      return
    }
    try await Task.sleep(for: .milliseconds(20))
  }
  throw TimeoutError()
}

/// Writes the daemon's wire format: snake_case keys and RFC3339 timestamps. `DaemonJSON.encoder`
/// is the app's own encoder and emits numeric dates the client's decoder rejects.
let daemonEncoder: JSONEncoder = {
  let encoder = JSONEncoder()
  encoder.keyEncodingStrategy = .convertToSnakeCase
  encoder.dateEncodingStrategy = .iso8601
  return encoder
}()

func makeState(
  phase: DaemonState.Phase = .idle,
  morningPending: Bool = false,
  nextStage: DaemonState.Stage? = nil,
  owedStage: DaemonState.Stage? = nil,
  snoozeUntil: Date? = nil,
  phaseEndAt: Date? = nil,
  pausedRemaining: Int = 0,
  pausedFrom: DaemonState.Phase = .idle,
  completedToday: Int = 0,
  workSessionsInBlock: Int = 0,
  focusedTaskIds: [Int] = [],
  reminderRings: Int = 0,
  dayEnded: Bool = false,
  floatWhenWaiting: Bool = false,
  pausedTooLong: Bool = false,
  bounceDockWhenPaused: Bool = true,
) -> DaemonState {
  DaemonState(
    state: phase,
    phaseEndAt: phaseEndAt,
    pausedRemaining: pausedRemaining,
    pausedFrom: pausedFrom,
    completedToday: completedToday,
    workSessionsInBlock: workSessionsInBlock,
    longBreakEvery: 4,
    nextStage: nextStage,
    owedStage: owedStage,
    morningPending: morningPending,
    snoozeUntil: snoozeUntil,
    statusLine: phase.displayName,
    focusedTaskIds: focusedTaskIds,
    reminderRings: reminderRings,
    dayEnded: dayEnded,
    floatWindowWhenWaiting: floatWhenWaiting,
    pausedTooLong: pausedTooLong,
    bounceDockWhenPaused: bounceDockWhenPaused,
  )
}

// MARK: - StubReminderPresenter

/// Records what the app asked macOS to show, so posting and withdrawing can be checked without the
/// real notification centre, which no test process may reach.
final class StubReminderPresenter: ReminderPresenter {
  struct Post: Equatable {
    let title: String
    let body: String
  }

  /// What macOS answers when it will not accept the reminder; nil when it accepts.
  var refusal: Error?

  /// Whoever claimed the delegate. Weak: the responder that claims it owns this presenter, and a
  /// strong record here would keep the pair alive as a cycle for the rest of the run.
  private(set) weak var claimedDelegate: UNUserNotificationCenterDelegate?

  private(set) var registeredButtons = false
  private(set) var posts = [Post]()
  private(set) var morningPosts = [Post]()
  private(set) var withdrawals = 0
  private(set) var attentionRequests = 0
  private(set) var attentionCancels = 0
  private(set) var windowReveals = 0
  private(set) var chimes = 0

  func claimNotificationDelegate(_ delegate: UNUserNotificationCenterDelegate) {
    claimedDelegate = delegate
  }

  func registerReminderButtons() {
    registeredButtons = true
  }

  func chime() {
    chimes += 1
  }

  func postReminder(title: String, body: String) async throws {
    if let refusal {
      throw refusal
    }
    posts.append(Post(title: title, body: body))
  }

  func postMorningReminder(title: String, body: String) async throws {
    if let refusal {
      throw refusal
    }
    morningPosts.append(Post(title: title, body: body))
  }

  func withdrawReminder() {
    withdrawals += 1
  }

  func requestAttention() {
    attentionRequests += 1
  }

  func cancelAttention() {
    attentionCancels += 1
  }

  func showWindowWithoutFocus() {
    windowReveals += 1
  }
}

func makeTask(id: Int, description: String = "task", done: Bool = false) -> TaskItem {
  TaskItem(id: id, description: description, done: done, createdAt: Date(), completedAt: Date())
}

/// Hosts a view in a real AppKit window and lays it out, so SwiftUI builds the AppKit views its
/// body describes and runs its lifecycle — `.onAppear`, and the focus it asks for — against them.
/// The window is deliberately never made key: `makeKeyAndOrderFront` hands the keyboard to the
/// window's own initial first responder, which would mask whether the view asked for focus itself.
@MainActor
func hostInWindow(_ rootView: some View) -> (view: NSHostingView<some View>, window: NSWindow) {
  let hosting = NSHostingView(rootView: rootView)
  hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
  let window = NSWindow(
    contentRect: hosting.frame,
    styleMask: [.titled, .closable, .fullSizeContentView],
    backing: .buffered,
    defer: false,
  )
  window.contentView = hosting
  hosting.layoutSubtreeIfNeeded()
  return (hosting, window)
}

/// `.onAppear` runs a runloop turn after the view is laid out, and the focus it asks for reaches
/// AppKit a turn or two after that, so the window is asked repeatedly rather than once. Shared by
/// every row whose `.onAppear` claims the keyboard: `NewTaskRowTests`, `LunchEntryRowTests`,
/// `MeetingEntryRowTests`, `SnoozeEntryRowTests`.
@MainActor
func waitForKeyboard(in field: NSControl, of window: NSWindow) {
  let deadline = Date().addingTimeInterval(2)
  while Date() < deadline, (window.firstResponder as? NSView)?.isDescendant(of: field) != true {
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
  }
}

/// Walks the AppKit view tree SwiftUI builds to find a `TextField`'s field. Matched by class-name
/// substring, since the type SwiftUI bridges to is not public API.
func findTextField(in view: NSView) -> NSControl? {
  if "\(type(of: view))".contains("AppKitTextField"), let control = view as? NSControl {
    return control
  }
  for subview in view.subviews {
    if let found = findTextField(in: subview) {
      return found
    }
  }
  return nil
}

// MARK: - StubTransport

/// Replays a fixed set of SSE frames and then holds the stream open, the way a live daemon does
/// between state changes. Records what the client sends so tests can assert on it.
// `recorded` is only touched under `lock`; DaemonTransport requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class StubTransport: DaemonTransport, @unchecked Sendable {

  // MARK: Lifecycle

  init(states: [DaemonState], tasks: TaskList = TaskList()) throws {
    frames = try states.map { try daemonEncoder.encode($0) }
    taskList = try daemonEncoder.encode(tasks)
  }

  // MARK: Internal

  struct Request: Equatable {
    let method: String
    let path: String
    let body: String
  }

  /// What every non-tasks request replies with; a non-2xx status makes the client raise a refusal.
  var commandStatus = 200

  /// The body to return for `GET /v1/stats`; nil means 404.
  var statsBody: Data?

  var requests: [Request] {
    lock.withLock { recorded }
  }

  /// Whether the client has asked for the event stream yet. A frame sent before it has is yielded
  /// into nothing, so a test that feeds the stream waits for this first.
  var isStreaming: Bool {
    lock.withLock { live != nil }
  }

  /// Everything but the task-list refresh the client runs after each frame.
  var commands: [Request] {
    requests.filter { $0.path != Self.tasksPath }
  }

  func request(_ method: String, _ path: String, body: Data?) async throws -> HTTPResponse {
    let request = Request(
      method: method,
      path: path,
      body: body.map { String(decoding: $0, as: UTF8.self) } ?? "",
    )
    lock.withLock { recorded.append(request) }
    if path == Self.tasksPath {
      return HTTPResponse(status: 200, headers: [:], body: taskList)
    }
    if path == Self.statsPath {
      if let statsBody {
        return HTTPResponse(status: 200, headers: [:], body: statsBody)
      } else {
        return HTTPResponse(status: 404, headers: [:], body: Self.commandReply)
      }
    }
    return HTTPResponse(status: commandStatus, headers: [:], body: Self.commandReply)
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
      lock.withLock { live = continuation }
      for frame in frames {
        continuation.yield(frame)
      }
    }
  }

  /// Feeds one more state down the open stream, for tests that need the client to see states
  /// arrive one at a time rather than all together at connection.
  func send(_ state: DaemonState) throws {
    let frame = try daemonEncoder.encode(state)
    lock.withLock { live }?.yield(frame)
  }

  // MARK: Private

  private static let tasksPath = "/v1/tasks"
  private static let statsPath = "/v1/stats"
  private static let commandReply = Data(#"{"message":"ok"}"#.utf8)

  private let frames: [Data]
  private let taskList: Data
  private let lock = NSLock()
  private var recorded = [Request]()

  /// The open stream's continuation, once the client has asked for one.
  private var live: AsyncThrowingStream<Data, Error>.Continuation?

}

// MARK: - UnreachableDaemonTransport

/// A transport that refuses the event stream, the way it does when the daemon is not running.
final class UnreachableDaemonTransport: DaemonTransport, Sendable {

  // MARK: Lifecycle

  init(message: String = "no daemon") {
    self.message = message
  }

  // MARK: Internal

  func request(_: String, _: String, body _: Data?) async throws -> HTTPResponse {
    throw DaemonError.transport(message)
  }

  func events(_: String) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { $0.finish(throwing: DaemonError.transport(self.message)) }
  }

  // MARK: Private

  private let message: String

}

// MARK: - RecordingAgentService

/// The launchd job as a recorder: it notes what it was asked to do instead of running
/// `launchctl`, so the service verbs the menu bar offers can be exercised without booting out
/// the agent — and the daemon — of the machine running the tests.
// `recorded` is only touched under `lock`; LaunchAgentService requires Sendable.
// swiftlint:disable:next no_unchecked_sendable
final class RecordingAgentService: LaunchAgentService, @unchecked Sendable {

  // MARK: Internal

  enum Call: Equatable {
    case register
    case unregister
  }

  /// What a fresh machine reports: nothing registered, so `ensureAgentRegistered` registers once
  /// rather than reloading (`AgentRegistrationPlan.steps(for:)`).
  var status: AgentStatus {
    .notRegistered
  }

  var calls: [Call] {
    lock.withLock { recorded }
  }

  func register() throws {
    lock.withLock { recorded.append(.register) }
  }

  func unregister() throws {
    lock.withLock { recorded.append(.unregister) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var recorded = [Call]()

}

/// An app whose launchd agent is a recorder rather than the machine's own.
@MainActor
func makeEnvironment(transport: DaemonTransport, agent: LaunchAgentService) -> AppEnvironment {
  AppEnvironment(transport: transport, registrar: SMAppServiceRegistrar(agent: agent))
}

// MARK: - Reading a built SwiftUI tree

// SwiftUI cannot render a view in a test process, but it does not have to: what a builder block
// built is still there in the value it returned. Two things are readable, and between them they
// cover a body statement by statement.
//
// The *shape* is the value's own type. `some View` and `some Commands` erase nothing structural:
// each statement a builder block contributes becomes a generic parameter, so a statement that
// stops being built changes the type of `body`. `shape(of:)` spells that out.
//
// The *wiring* is everything a modifier stored as a value — an action closure, a sheet's content
// closure, the branch an `if` filled in — reachable with `Mirror` and callable once cast.
//
// These helpers are the vocabulary for both, shared rather than re-derived per test file.

/// A value's type, as SwiftUI spells it, with the module names taken out so an expected shape
/// reads as the view it describes. The opaque context SwiftUI's private types are nested in goes
/// too: it is an address, and it differs between runs.
func shape(of value: Any) -> String {
  var text = String(reflecting: type(of: value))
  for module in ["SwiftUI.", "ThrowntomUI.", "ThrowntomClient.", "Swift."] {
    text = text.replacingOccurrences(of: module, with: "")
  }
  return text.replacingOccurrences(
    of: #"\(unknown context at \$[0-9a-f]+\)\."#,
    with: "",
    options: .regularExpression,
  )
}

/// The name a shape starts with, without its generic parameters.
func head(_ value: Any) -> String {
  String(shape(of: value).prefix { $0 != "<" })
}

func child(_ label: String, of value: Any) throws -> Any {
  let children = Mirror(reflecting: value).children
  return try XCTUnwrap(
    children.first { $0.label == label }?.value,
    "no \(label) in \(shape(of: value)), which has \(children.compactMap(\.label))",
  )
}

func content(of value: Any) throws -> Any {
  try child("content", of: value)
}

/// The statements a builder block contributed, out of the `TupleView` it packed them into.
func tupleParts(of value: Any) throws -> [Any] {
  Mirror(reflecting: try child("value", of: value)).children.map(\.value)
}

/// The block a stack lays out, which `VStack` and its siblings keep behind the variadic tree.
func stackContent(of view: Any) throws -> Any {
  try content(of: try child("_tree", of: view))
}

/// A statement's position in a builder block, read as a failure rather than a trap when the
/// statement is gone: an out-of-range read kills the whole test process, and a mutation run
/// reads a dead process as a crash rather than as the mutant having been caught.
func part(_ index: Int, of parts: [Any]) throws -> Any {
  try XCTUnwrap(
    parts.indices.contains(index) ? parts[index] : nil,
    "nothing at position \(index): the block built \(parts.count) of them",
  )
}

/// Whether an `if` without an `else` built anything. A builder leaves one as an `Optional` whose
/// type names the view either way, so the type says what would be drawn and this says whether it
/// is being drawn now.
func isBuilt(_ value: Any) -> Bool {
  Mirror(reflecting: value).displayStyle == .optional && Mirror(reflecting: value).children.first != nil
}

/// Which half of an `if`/`else` the builder filled in.
func branch(of view: Any) throws -> String {
  try XCTUnwrap(Mirror(reflecting: try child("storage", of: view)).children.first?.label)
}

/// What that half was filled in with.
func branchContent(of view: Any) throws -> Any {
  try XCTUnwrap(Mirror(reflecting: try child("storage", of: view)).children.first?.value)
}

/// A view with what was wrapped around it taken back off: every `.modifier` layer, and the
/// `if`/`else` storage that holds only the branch that was built.
func unwrapped(_ view: Any) throws -> Any {
  var result = view
  while true {
    switch head(result) {
    case "ModifiedContent": result = try content(of: result)
    case "_ConditionalContent": result = try branchContent(of: result)
    default: return result
    }
  }
}

/// Every modifier applied to a view, innermost first — one per `.` in the source, in the order
/// the source wrote them.
func modifierLayers(of view: Any) -> [Any] {
  var layers = [Any]()
  var node = view
  while
    let modifier = Mirror(reflecting: node).children.first(where: { $0.label == "modifier" })?.value,
    let inner = Mirror(reflecting: node).children.first(where: { $0.label == "content" })?.value
  {
    layers.append(modifier)
    node = inner
  }
  return layers.reversed()
}

// MARK: - Reading a built SplitChip

/// The `SplitChip` a chip's `body` has to be built from, checked by shape before its own `body`
/// is read — calling `.body` on whatever a wrong-shaped value turned out to be (`EmptyView`'s is
/// `Never`) traps the process, which a mutant that empties the whole statement would otherwise
/// turn into an unkillable crash instead of a clean, assertable failure.
@MainActor
func splitChip(of chip: some View) throws -> some View {
  let built = chip.body
  guard shape(of: built).hasPrefix("SplitChip<") else {
    XCTFail("\(shape(of: built)) is not a SplitChip")
    throw UnexpectedShapeError()
  }
  return built
}

/// The label region's own `Button` action — a `SplitChip`'s primary tap — reached the same way
/// `MenuCommandsTests.fire` reaches a menu button's stored action. Shared by `LunchChipTests`,
/// `MeetingChipTests` and `SnoozeChipTests`, whose chips are all built from `SplitChip`.
@MainActor
func splitChipPrimaryAction(_ chip: some View) throws -> @MainActor () -> Void {
  let parts = try tupleParts(of: try stackContent(of: try unwrapped(try splitChip(of: chip).body)))
  let labelRegion = try unwrapped(try part(0, of: parts))
  return try XCTUnwrap(
    try child("closure", of: try child("action", of: labelRegion)) as? @MainActor () -> Void,
    "\(shape(of: labelRegion)) has no button action to press",
  )
}

/// The chevron's own `MenuGroups`, ready to be asked what it built for an item — the same
/// `MenuGroupsLabels` technique `MenuCommandsTests` uses to reach `AppMenus`' menus.
@MainActor
func splitChipMenuGroups(_ chip: some View) throws -> MenuGroupsLabels {
  let parts = try tupleParts(of: try stackContent(of: try unwrapped(try splitChip(of: chip).body)))
  let chevron = try unwrapped(try part(1, of: parts))
  return try XCTUnwrap(
    try child("content", of: chevron) as? MenuGroupsLabels,
    "\(shape(of: chevron)) has no MenuGroups content",
  )
}

// MARK: - RecordingRegistrar

/// A launchd stand-in that records what it was asked to do, so the window's service controls can
/// be exercised without registering or booting out an agent on the machine running the tests.
// Every mutable member is read and written under `lock`.
// swiftlint:disable:next no_unchecked_sendable
final class RecordingRegistrar: LaunchAgentRegistrar, @unchecked Sendable {

  // MARK: Internal

  enum Call: Equatable {
    case register
    case stop
  }

  var calls: [Call] {
    lock.withLock { recorded }
  }

  func ensureAgentRegistered() async throws {
    lock.withLock { recorded.append(.register) }
  }

  func stopAgent() async throws {
    lock.withLock { recorded.append(.stop) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var recorded = [Call]()

}

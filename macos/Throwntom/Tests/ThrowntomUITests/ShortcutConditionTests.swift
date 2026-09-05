import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// That each row's "when this applies" is the rule the code actually follows.
///
/// The condition is prose sitting a long way from `TimerActions.available(for:)`, and nothing in
/// the type system ties the two together — the same gap `MenuBindingTests` closes between a hint
/// and its binding. Left open, a verb that changes when it is offered leaves the sheet teaching the
/// old rule, which is worse than the dim alone: a reader can check a dim against the screen and
/// cannot check a sentence against anything.
///
/// So the phases are swept and the answer read out of `available` rather than restated: the table
/// below is the wording paired with the phases it claims, and the sweep is what decides.
@MainActor
final class ShortcutConditionTests: XCTestCase {

  // MARK: Internal

  func testEachTimerConditionNamesThePhasesItsVerbIsActuallyOfferedIn() {
    for (wording, actions, phases) in Self.claims {
      for action in actions {
        XCTAssertEqual(action.availability, wording, "\(action)")
      }
      XCTAssertEqual(
        Self.phasesOffering(actions),
        phases,
        "\"\(wording)\" is not when \(actions) is offered",
      )
    }
  }

  /// The verbs with no key bind nothing and appear on no row, so they claim nothing either.
  func testTheVerbsWithNoShortcutClaimNoCondition() {
    for action in TimerAction.allCases where action.shortcutHint.isEmpty {
      XCTAssertEqual(action.availability, "", "\(action)")
    }
    XCTAssertEqual(TaskAction.newTask.availability, "")
  }

  /// Every task verb but New Task needs a row, which is what `TaskWindowModel.canPerform` says with
  /// no selection.
  func testTheTaskConditionIsWhatTheModelActuallyRequires() {
    let model = TaskWindowModel()
    model.sync(tasks: TaskList(active: [makeTask(id: 1)], completed: []), focusedTaskIDs: [])

    for action in TaskAction.allCases {
      let needsARow = !action.availability.isEmpty
      XCTAssertEqual(model.canPerform(action, on: nil), !needsARow, "\(action) with no selection")
      XCTAssertTrue(model.canPerform(action, on: 1), "\(action) on a row")
    }
  }

  /// The two panels are the View commands that need a daemon; the cheat sheet and the config file
  /// are local, and say so by claiming no condition.
  func testTheViewConditionIsWhatTheMenuActuallyRequires() {
    let withADaemon = MenuModel.view(showsShortcuts: false, daemonAvailable: true)
    let without = MenuModel.view(showsShortcuts: false, daemonAvailable: false)

    for item in withADaemon.items {
      XCTAssertTrue(item.isEnabled, "\(item.action)")
    }
    for item in without.items {
      let needsADaemon = !item.action.availability.isEmpty
      XCTAssertEqual(item.isEnabled, !needsADaemon, "\(item.action) with no daemon")
    }
  }

  // MARK: Private

  /// Each wording, the verbs that carry it, and the phases it claims they are offered in.
  private static let claims: [(wording: String, actions: Set<TimerAction>, phases: Set<DaemonState.Phase>)] = [
    ("while idle", [.start], [.idle]),
    ("when a phase has ended", [.confirm], [.awaitingConfirm]),
    ("while a phase is running or paused", [.pause, .resume], [.work, .shortBreak, .longBreak, .lunch, .meeting, .paused]),
    // Skip is absent from a meeting deliberately: ending one is what the meeting chip does, and
    // it credits the time rather than discarding it (`TimerActions.available(for:)`).
    ("while a phase is running", [.skip], [.work, .shortBreak, .longBreak, .lunch]),
    ("while a reminder is waiting", [.snooze], [.idle, .awaitingConfirm]),
  ]

  /// The phases in which the daemon would offer any of `actions`. Swept with a morning reminder
  /// pending, because that is the idle state Snooze is for: the sheet's Snooze row stands for the
  /// morning nudge as much as for a finished phase.
  private static func phasesOffering(_ actions: Set<TimerAction>) -> Set<DaemonState.Phase> {
    var offering = Set<DaemonState.Phase>()
    for phase in DaemonState.Phase.allCases {
      let available = Set(TimerActions.available(for: makeState(phase: phase, morningPending: true)))
      if !available.isDisjoint(with: actions) {
        offering.insert(phase)
      }
    }
    return offering
  }

}

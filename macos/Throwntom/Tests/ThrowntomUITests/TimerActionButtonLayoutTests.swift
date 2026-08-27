import XCTest
@testable import ThrowntomClient
@testable import ThrowntomUI

/// The layout decision behind the toolbar bug: the popover's inline hint (title + Spacer + hint)
/// only belongs in the popover's vertical menu. In a toolbar the Spacer breaks layout, so the
/// toolbar variant must never carry it, even for actions that do have a shortcut hint.
@MainActor
final class TimerActionButtonLayoutTests: XCTestCase {
    private func makeClient() throws -> DaemonClient {
        let environment = AppEnvironment(transport: try StubTransport(states: []))
        return environment.client
    }

    func testPopoverLayoutShowsInlineHintOnlyWhenActionHasOne() throws {
        let client = try makeClient()

        XCTAssertTrue(TimerActionButton(action: .start, client: client, layout: .popover).showsInlineHint)
        XCTAssertFalse(TimerActionButton(action: .skipToday, client: client, layout: .popover).showsInlineHint)
        XCTAssertFalse(TimerActionButton(action: .newCycle, client: client, layout: .popover).showsInlineHint)
    }

    func testToolbarLayoutNeverShowsTheInlineHintEvenWhenTheActionHasOne() throws {
        let client = try makeClient()

        for action in TimerAction.allCases {
            XCTAssertFalse(
                TimerActionButton(action: action, client: client, layout: .toolbar).showsInlineHint,
                "\(action) must not carry the popover's Spacer layout in the toolbar")
        }
    }

    func testEveryToolbarActionAcrossAllStatesRendersWithoutTheInlineHint() throws {
        let client = try makeClient()
        let states: [DaemonState] = [
            makeState(.idle),
            makeState(.idle, morningPending: true),
            makeState(.work),
            makeState(.shortBreak),
            makeState(.longBreak),
            makeState(.paused),
            makeState(.awaitingConfirm),
        ]

        for state in states {
            for action in TimerActions.available(for: state) {
                XCTAssertFalse(
                    TimerActionButton(action: action, client: client, layout: .toolbar).showsInlineHint,
                    "\(action) in \(state.state) must render without the popover's Spacer")
            }
        }
    }

    private func makeState(_ phase: DaemonState.Phase, morningPending: Bool = false) -> DaemonState {
        DaemonState(state: phase, phaseEndAt: nil, pausedRemaining: 0, completedToday: 0, workSessionsInBlock: 0,
              longBreakEvery: 4, nextStage: nil, morningPending: morningPending, snoozeUntil: nil,
              statusLine: "", focusedTaskIds: [])
    }
}

import XCTest
@testable import ThrowntomClient

final class StateDecodingTests: XCTestCase {
  /// Captured from GET /v1/state on a fresh throwntomd.
  static let idleJSON = #"{"state":"idle","phase_end_at":null,"paused_remaining":0,"paused_from":"idle","completed_today":0,"work_sessions_in_block":0,"long_break_every":4,"next_stage":null,"owed_stage":{"state":"work","duration":1500},"morning_pending":true,"snooze_until":null,"status_line":"Idle  Today: 0  Cycle: 0/4","focused_task_ids":[],"reminder_rings":0,"day_ended":false,"float_window_when_waiting":false,"paused_too_long":false,"bounce_dock_when_paused":true}"#

  static let workJSON = #"{"state":"work","phase_end_at":"2026-08-25T10:25:00.123456789-07:00","paused_remaining":0,"paused_from":"idle","completed_today":3,"work_sessions_in_block":1,"long_break_every":4,"next_stage":{"state":"short_break","duration":300},"owed_stage":null,"morning_pending":false,"snooze_until":"2026-08-25T09:00:00Z","status_line":"Pomodoro  12:34  Today: 3  Cycle: 1/4","focused_task_ids":[3,7],"reminder_rings":2,"day_ended":false,"float_window_when_waiting":false,"paused_too_long":false,"bounce_dock_when_paused":true}"#

  static let pausedJSON = #"{"state":"paused","phase_end_at":null,"paused_remaining":900,"paused_from":"long_break","completed_today":4,"work_sessions_in_block":0,"long_break_every":4,"next_stage":{"state":"work","duration":1500},"owed_stage":null,"morning_pending":false,"snooze_until":null,"status_line":"Paused","focused_task_ids":[],"reminder_rings":0,"day_ended":false,"float_window_when_waiting":false,"paused_too_long":false,"bounce_dock_when_paused":true}"#

  func testDecodesPausedFrom() throws {
    let s = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.pausedJSON.utf8))
    XCTAssertEqual(s.state, .paused)
    XCTAssertEqual(s.pausedFrom, .longBreak)
    let idle = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8))
    XCTAssertEqual(idle.pausedFrom, .idle)
  }

  /// The wire key the daemon writes for an ended work day; `internal/core/state_test.go` holds
  /// the daemon to the same name.
  func testDecodesTheEndedDayFlag() throws {
    let ended = Self.idleJSON.replacingOccurrences(of: #""day_ended":false"#, with: #""day_ended":true"#)
    XCTAssertTrue(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(ended.utf8)).dayEnded)
    XCTAssertFalse(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8)).dayEnded)
  }

  /// The wire key the daemon writes for the floating-window setting; the daemon is held to the
  /// same name in `internal/core/state_test.go`.
  func testDecodesTheFloatingWindowSetting() throws {
    let on = Self.idleJSON.replacingOccurrences(
      of: #""float_window_when_waiting":false"#,
      with: #""float_window_when_waiting":true"#,
    )
    XCTAssertTrue(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(on.utf8)).floatWindowWhenWaiting)
    XCTAssertFalse(
      try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8)).floatWindowWhenWaiting
    )
  }

  /// The wire key the daemon writes for a pause that has outlasted its threshold; the daemon is
  /// held to the same name in `internal/core/state_test.go`.
  func testDecodesTheForgottenPauseFlag() throws {
    let forgotten = Self.pausedJSON.replacingOccurrences(
      of: #""paused_too_long":false"#,
      with: #""paused_too_long":true"#,
    )
    XCTAssertTrue(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(forgotten.utf8)).pausedTooLong)
    XCTAssertFalse(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.pausedJSON.utf8)).pausedTooLong)
  }

  /// The wire key the daemon writes for the Dock-bounce setting; the daemon is held to the same
  /// name in `internal/core/state_test.go`.
  func testDecodesTheBounceDockWhenPausedSetting() throws {
    let off = Self.idleJSON.replacingOccurrences(
      of: #""bounce_dock_when_paused":true"#,
      with: #""bounce_dock_when_paused":false"#,
    )
    XCTAssertFalse(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(off.utf8)).bounceDockWhenPaused)
    XCTAssertTrue(
      try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8)).bounceDockWhenPaused
    )
  }

  func testDecodesIdleState() throws {
    let s = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8))
    XCTAssertEqual(s.state, .idle)
    XCTAssertNil(s.phaseEndAt)
    XCTAssertNil(s.nextStage)
    XCTAssertTrue(s.morningPending)
    XCTAssertNil(s.snoozeUntil)
    XCTAssertEqual(s.statusLine, "Idle  Today: 0  Cycle: 0/4")
    XCTAssertEqual(s.focusedTaskIds, [])
    XCTAssertEqual(s.longBreakEvery, 4)
  }

  func testDecodesWorkStateWithGoTimestamps() throws {
    let s = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.workJSON.utf8))
    XCTAssertEqual(s.state, .work)
    XCTAssertEqual(s.phaseEndAt?.timeIntervalSince1970 ?? 0, 1_787_678_700.123, accuracy: 0.001)
    XCTAssertEqual(s.nextStage, DaemonState.Stage(state: .shortBreak, duration: 300))
    XCTAssertEqual(s.snoozeUntil?.timeIntervalSince1970 ?? 0, 1_787_648_400, accuracy: 0.001)
    XCTAssertEqual(s.completedToday, 3)
    XCTAssertEqual(s.workSessionsInBlock, 1)
    XCTAssertEqual(s.focusedTaskIds, [3, 7])
  }

  /// throwntom-46y. The wire key the daemon writes for the phase a start would enter;
  /// `internal/core/state_test.go` holds the daemon to the same name. Mutually exclusive with
  /// `next_stage` by construction there: one is what confirm moves on to, the other what start
  /// begins, and only an idle timer owes anything.
  func testDecodesTheOwedStage() throws {
    let idle = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.idleJSON.utf8))
    XCTAssertEqual(idle.owedStage, DaemonState.Stage(state: .work, duration: 1500))
    XCTAssertNil(idle.nextStage)

    let work = try DaemonJSON.decoder.decode(DaemonState.self, from: Data(Self.workJSON.utf8))
    XCTAssertNil(work.owedStage)
    XCTAssertEqual(work.nextStage, DaemonState.Stage(state: .shortBreak, duration: 300))
  }

  func testDecodesEveryPhaseName() throws {
    for (raw, phase) in [
      ("idle", DaemonState.Phase.idle),
      ("work", .work),
      ("short_break", .shortBreak),
      ("long_break", .longBreak),
      ("lunch", .lunch),
      ("awaiting_confirm", .awaitingConfirm),
      ("paused", .paused),
    ] {
      let json = Self.idleJSON.replacingOccurrences(of: #""state":"idle""#, with: #""state":"\#(raw)""#)
      XCTAssertEqual(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(json.utf8)).state, phase, raw)
    }
  }

  func testDecodesTaskListWithZeroCompletedAt() throws {
    let json = #"{"active":[{"id":1,"description":"write plan","done":false,"created_at":"2026-08-25T20:14:37.5-07:00","completed_at":"0001-01-01T00:00:00Z"}],"completed":[{"id":2,"description":"old","done":true,"created_at":"2026-08-24T08:00:00Z","completed_at":"2026-08-24T09:00:00Z"}]}"#
    let list = try DaemonJSON.decoder.decode(TaskList.self, from: Data(json.utf8))
    XCTAssertEqual(list.active.map(\.id), [1])
    XCTAssertEqual(list.active[0].description, "write plan")
    XCTAssertFalse(list.active[0].done)
    XCTAssertEqual(list.completed.map(\.description), ["old"])
    XCTAssertTrue(list.completed[0].done)
  }

  func testRejectsUnparseableTime() {
    let json = Self.workJSON.replacingOccurrences(of: "2026-08-25T10:25:00.123456789-07:00", with: "yesterday")
    XCTAssertThrowsError(try DaemonJSON.decoder.decode(DaemonState.self, from: Data(json.utf8)))
  }
}

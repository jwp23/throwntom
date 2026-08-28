import XCTest
@testable import ThrowntomClient

final class StateDecodingTests: XCTestCase {
  /// Captured from GET /v1/state on a fresh throwntomd.
  static let idleJSON = #"{"state":"idle","phase_end_at":null,"paused_remaining":0,"completed_today":0,"work_sessions_in_block":0,"long_break_every":4,"next_stage":null,"morning_pending":true,"snooze_until":null,"status_line":"Idle  Today: 0  Cycle: 0/4","focused_task_ids":[]}"#

  static let workJSON = #"{"state":"work","phase_end_at":"2026-08-25T10:25:00.123456789-07:00","paused_remaining":0,"completed_today":3,"work_sessions_in_block":1,"long_break_every":4,"next_stage":{"state":"short_break","duration":300},"morning_pending":false,"snooze_until":"2026-08-25T09:00:00Z","status_line":"Pomodoro  12:34  Today: 3  Cycle: 1/4","focused_task_ids":[3,7]}"#

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
    XCTAssertEqual(s.nextStage, DaemonState.NextStage(state: .shortBreak, duration: 300))
    XCTAssertEqual(s.snoozeUntil?.timeIntervalSince1970 ?? 0, 1_787_648_400, accuracy: 0.001)
    XCTAssertEqual(s.completedToday, 3)
    XCTAssertEqual(s.workSessionsInBlock, 1)
    XCTAssertEqual(s.focusedTaskIds, [3, 7])
  }

  func testDecodesEveryPhaseName() throws {
    for (raw, phase) in [
      ("idle", DaemonState.Phase.idle),
      ("work", .work),
      ("short_break", .shortBreak),
      ("long_break", .longBreak),
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

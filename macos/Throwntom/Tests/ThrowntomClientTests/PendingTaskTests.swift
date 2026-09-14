import XCTest
@testable import ThrowntomClient

/// `PendingTask` holds an event stream's reader, and cancelling a task runs that task's own
/// cancellation handlers on whichever thread asked for the cancel. The reader's handlers close a
/// socket and resume a pending call, so whoever drops the stream — the main thread, as often as
/// not — must not be left waiting on them.
///
/// Both waits here are bounded: a cancel that never returns has to fail on a deadline, because a
/// test that waited for it would hang the whole suite.
final class PendingTaskTests: XCTestCase {

  func testCancelDoesNotWaitForTheTasksCancellationHandler() {
    // Held for the duration of the test, so the handler blocks exactly as one that cannot take
    // the socket's own lock would.
    let held = NSLock()
    held.lock()
    defer { held.unlock() }
    let waiting = expectation(description: "the reader to reach its cancellable work")
    let handlerStarted = expectation(description: "the reader's cancellation handler to start")
    let returned = expectation(description: "the cancel to return")
    let reader = PendingTask()
    reader.hold(Task {
      await withTaskCancellationHandler {
        waiting.fulfill()
        try? await Task.sleep(for: .seconds(30))
      } onCancel: {
        handlerStarted.fulfill()
        held.lock()
        held.unlock()
      }
    })
    // Cancelling before the reader is inside its work would run the handler on the reader's own
    // thread, which is not the case under test.
    wait(for: [waiting], timeout: 2)

    // On a thread of its own: a cancel that does wait would otherwise take the test with it.
    Thread.detachNewThread {
      reader.cancel()
      returned.fulfill()
    }

    wait(for: [handlerStarted, returned], timeout: 2)
  }

  /// The cancel can arrive before the task does — a consumer that drops the event stream the
  /// moment it has it. The task handed over afterwards is stopped rather than left reading a
  /// socket nobody is listening to.
  func testATaskHeldAfterACancelIsStoppedAnyway() {
    let stopped = expectation(description: "the late task to be cancelled")
    let held = expectation(description: "the handover to return")
    let reader = PendingTask()
    reader.cancel()

    // On a thread of its own: a handover that does not return would otherwise take the test with
    // it, and the point of the deadline below is that it says so instead.
    Thread.detachNewThread {
      reader.hold(Task {
        await withTaskCancellationHandler {
          try? await Task.sleep(for: .seconds(30))
        } onCancel: {
          stopped.fulfill()
        }
      })
      held.fulfill()
    }

    wait(for: [held, stopped], timeout: 2)
  }

}

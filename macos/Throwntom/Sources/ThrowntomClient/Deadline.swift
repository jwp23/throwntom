import Foundation

/// Runs `operation`, failing the call with `DaemonError.timedOut` once `timeout` has passed.
///
/// The work runs on a task of its own rather than in a task group, because a group cannot return
/// until every child has, and cancelling a child is a request rather than a guarantee: a child
/// suspended on a continuation nothing resumes stays suspended, cancelled or not. The deadline
/// here resumes the caller itself and leaves the work behind, so the bound the caller was promised
/// holds even then. Work left behind is cancelled but not waited for, so work that cannot answer a
/// cancel runs until the process exits — the price of answering the caller at all.
func withDeadline<T: Sendable>(
  _ timeout: Duration,
  operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
  // A task group's children start cancelled when their parent already is; a task of its own does
  // not, so a caller that has been cancelled before it got here is answered before any work
  // starts rather than after something it never wanted had been set going.
  try Task.checkCancellation()
  // The stream is the handoff: whichever of the two tasks arrives first ends it, and the loser's
  // outcome is dropped rather than overwriting the result the caller already has.
  let (outcomes, sink) = AsyncThrowingStream<T, Error>.makeStream()
  let work = Task {
    do {
      sink.yield(try await operation())
      sink.finish()
    } catch {
      sink.finish(throwing: error)
    }
  }
  let deadline = Task {
    try await Task.sleep(for: timeout)
    sink.finish(throwing: DaemonError.timedOut(after: timeout))
  }
  defer { deadline.cancel() }

  var arrivals = outcomes.makeAsyncIterator()
  do {
    guard let value = try await arrivals.next() else {
      // Cancelling the caller terminates the stream without ending it, and the work it was
      // waiting on is still out there; the caller asked to stop, so that is what it hears.
      throw CancellationError()
    }
    return value
  } catch {
    // Cancelling runs the work's own cancellation handlers on this thread, and work the caller has
    // stopped waiting for is exactly the work that may never get through them. So the cancel goes
    // on a task of its own. (After an ordinary failure the work has already finished, and cancelling
    // a finished task returns at once.) What that costs is a pool thread: a handler that blocks for
    // good holds the cooperative thread it runs on rather than suspending, and the deadline above
    // needs that same pool to fire. Accepted, because it gives way one thread at a time where
    // cancelling here would stop this caller dead on the first one.
    Task.detached { work.cancel() }
    throw error
  }
}

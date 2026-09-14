import Foundation

/// Runs `operation`, failing the call with `DaemonError.timedOut` once `timeout` has passed.
func withDeadline<T: Sendable>(
  _ timeout: Duration,
  operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await operation() }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw DaemonError.timedOut(after: timeout)
    }
    defer { group.cancelAll() }
    guard let value = try await group.next() else {
      throw DaemonError.transport("the call ended without a result")
    }
    return value
  }
}

import Foundation

/// One task as stored by the daemon. Named TaskItem to avoid clashing with Swift concurrency's Task.
public struct TaskItem: Codable, Equatable, Identifiable, Sendable {
  public var id: Int
  public var description: String
  public var done: Bool
  public var createdAt: Date
  /// Go's zero time (year 1) for tasks that are not done.
  public var completedAt: Date
}

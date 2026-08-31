/// GET /v1/tasks response; both arrays are always present.
public struct TaskList: Codable, Equatable, Sendable {
  public init(active: [TaskItem] = [], completed: [TaskItem] = []) {
    self.active = active
    self.completed = completed
  }

  public var active: [TaskItem]
  public var completed: [TaskItem]

  /// The active tasks named by `ids`, in list order. Ids that name no active task are dropped.
  public func focused(ids: [Int]) -> [TaskItem] {
    let wanted = Set(ids)
    return active.filter { wanted.contains($0.id) }
  }
}

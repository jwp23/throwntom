import Foundation

/// Builds the command strings the daemon's task grammar accepts (internal/core/tasks.go).
public enum TaskCommands {
  public static func addTask(_ description: String) throws -> String {
    guard description.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
      throw TaskCommandError.controlCharacters
    }
    let words = description.split(whereSeparator: { $0.isWhitespace })
    guard !words.isEmpty else { throw TaskCommandError.emptyDescription }
    return "task add " + words.joined(separator: " ")
  }

  /// 1-based position of a task in the active list; nil for completed or unknown tasks.
  public static func position(of id: Int, in list: TaskList) -> Int? {
    list.active.firstIndex { $0.id == id }.map { $0 + 1 }
  }

  /// Command for a selected task. `focused` decides between focus and unfocus. newTask has no line; use addTask.
  public static func line(for action: TaskAction, position: Int, focused: Bool) -> String {
    switch action {
    case .newTask: ""
    case .complete: "task done \(position)"
    case .delete: "task remove \(position)"
    case .focus: focused ? "task unfocus \(position)" : "task focus \(position)"
    case .moveUp: "task up \(position)"
    case .moveDown: "task down \(position)"
    }
  }
}

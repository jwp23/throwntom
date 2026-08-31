import SwiftUI
import ThrowntomClient

struct TaskRow: View {
  let task: TaskItem
  let focused: Bool

  /// What the row reads as. Both of the things this row says about a task beyond its text — the
  /// star, and the line through a finished one — are drawn rather than written, so on a row read
  /// aloud they are not there at all. A completed task in particular was indistinguishable from an
  /// outstanding one: the strikethrough is the only difference, and strikethrough is silent.
  var label: String {
    var parts = [task.description]
    if focused {
      parts.append("focused")
    }
    if task.done {
      parts.append("completed")
    }
    return parts.joined(separator: ", ")
  }

  var body: some View {
    HStack {
      if focused {
        Image(systemName: "star.fill").foregroundStyle(.yellow)
      } else {
        Image(systemName: "circle")
      }
      Text(task.description)
        .strikethrough(task.done)
      Spacer()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }
}

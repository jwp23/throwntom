import SwiftUI
import ThrowntomClient

struct TaskRow: View {
  let task: TaskItem
  let focused: Bool
  /// The star's or circle's colour. Passed in rather than chosen here: the mark takes the text
  /// colour of the surface the row is drawn on, and only the caller knows which that is (see
  /// `PhaseScheme.taskMark`).
  let markColor: HexColor

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
      Image(systemName: focused ? "star.fill" : "circle")
        .foregroundStyle(markColor.color)
      Text(task.description)
        .strikethrough(task.done)
      Spacer()
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }
}

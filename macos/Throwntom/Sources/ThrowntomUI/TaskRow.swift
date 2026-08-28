import SwiftUI
import ThrowntomClient

struct TaskRow: View {
  let task: TaskItem
  let focused: Bool

  var body: some View {
    HStack {
      Image(systemName: focused ? "star.fill" : "circle")
        .foregroundStyle(focused ? .yellow : .secondary)
        .accessibilityLabel("Focused")
        .accessibilityHidden(!focused)
      Text(task.description)
        .strikethrough(task.done)
        .foregroundStyle(task.done ? .secondary : .primary)
      Spacer()
    }
    .padding(.vertical, 2)
  }
}

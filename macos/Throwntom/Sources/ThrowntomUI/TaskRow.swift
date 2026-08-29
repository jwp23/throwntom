import SwiftUI
import ThrowntomClient

struct TaskRow: View {
  let task: TaskItem
  let focused: Bool

  var body: some View {
    HStack {
      Group {
        if focused {
          Image(systemName: "star.fill").foregroundStyle(.yellow)
        } else {
          Image(systemName: "circle")
        }
      }
      .accessibilityLabel("Focused")
      .accessibilityHidden(!focused)
      Text(task.description)
        .strikethrough(task.done)
      Spacer()
    }
    .padding(.vertical, 2)
  }
}

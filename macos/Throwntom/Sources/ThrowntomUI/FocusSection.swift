import SwiftUI
import ThrowntomClient

/// The tasks the user chose to focus on. Absent entirely when there are none.
struct FocusSection: View {
  let tasks: [TaskItem]

  var body: some View {
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text("Focus").font(.caption).textCase(.uppercase)
        ForEach(tasks) { task in
          Label {
            Text(task.description)
          } icon: {
            Image(systemName: "star.fill").foregroundStyle(.yellow)
          }
          .accessibilityLabel(task.description)
        }
      }
    }
  }
}

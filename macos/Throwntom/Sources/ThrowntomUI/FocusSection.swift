import SwiftUI
import ThrowntomClient

/// The tasks the user chose to focus on. Absent entirely when there are none.
struct FocusSection: View {

  /// The window's answer to "what is this pomodoro for": body, like the next-stage line and the
  /// garden summary, at the medium weight `ShortcutHint` takes, so the list reads as its own thing
  /// rather than as more of the text around it. Stated here rather than inherited, so a change to
  /// the enclosing stack cannot quietly shrink it. Not larger: the phase name is the one headline.
  static let font = Font.body.weight(.medium)

  let tasks: [TaskItem]
  /// The ground these rows are drawn on, read for the star's colour alone.
  let scheme: PhaseScheme

  /// The star's colour: the ground's own text colour (see `PhaseScheme.taskMark`).
  var markColor: HexColor {
    scheme.taskMark
  }

  var body: some View {
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: 2) {
        Text("Focus").font(.caption).textCase(.uppercase)
        ForEach(tasks) { task in
          Label {
            Text(task.description)
          } icon: {
            Image(systemName: "star.fill").foregroundStyle(markColor.color)
          }
          .font(Self.font)
          .accessibilityLabel(task.description)
        }
      }
    }
  }

}

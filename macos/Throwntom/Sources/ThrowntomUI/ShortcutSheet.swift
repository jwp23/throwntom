import SwiftUI
import ThrowntomClient

/// ⌘/ — the cheat sheet. Esc or the button closes it.
struct ShortcutSheet: View {
  let environment: AppEnvironment

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
      ForEach(ShortcutList.sections(for: environment), id: \.name) { section in
        VStack(alignment: .leading, spacing: 3) {
          Text(section.name).font(.caption).textCase(.uppercase).foregroundStyle(.secondary)
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
            ForEach(section.entries) { entry in
              ShortcutRow(entry: entry)
            }
          }
        }
      }
      // Confirm and Keyboard Shortcuts read live rather than dim (`ShortcutList.sections`), which
      // answers for the window behind this sheet rather than for the sheet itself — stated here so
      // a reader who presses ⇧⏎ at a bright Confirm row and sees nothing happen can reconcile it.
      Text("Shown for the window behind this sheet").font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Done") { close() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(minWidth: 320)
    // The sheet is its own key window, so Esc must be handled here, not in MainWindow.
    .onExitCommand { close() }
  }

  func close() {
    environment.windowModel.showsShortcuts = false
  }
}

import SwiftUI
import ThrowntomClient

// MARK: - ShortcutList

/// Every shortcut the app binds, read from the same menu models the menus are built from.
enum ShortcutList {

  // MARK: Internal

  struct Entry: Equatable {
    let title: String
    let hint: String
  }

  struct Section: Equatable {
    let name: String
    let entries: [Entry]
  }

  @MainActor
  static func sections(for environment: AppEnvironment) -> [Section] {
    [
      Section(
        name: "Timer",
        entries: entries(MenuModel.timer(state: environment.client.state, isEditing: false)) { $0.shortcutHint },
      ),
      Section(name: "View", entries: entries(MenuModel.view(model: environment.windowModel)) { $0.shortcutHint }),
      Section(name: "Tasks", entries: entries(MenuModel.tasks(model: environment.model)) { $0.shortcutHint }),
      Section(name: "App", entries: entries(MenuModel.appConfig()) { $0.shortcutHint } + [
        // Quit is AppKit's own item, so it is the one shortcut no menu model owns.
        Entry(title: "Quit Throwntom", hint: "⌘Q")
      ]),
    ]
  }

  // MARK: Private

  private static func entries<Action>(_ menu: MenuModel<Action>, hint: (Action) -> String) -> [Entry] {
    menu.items.compactMap { item in
      let h = hint(item.action)
      return h.isEmpty ? nil : Entry(title: item.title, hint: h)
    }
  }

}

// MARK: - ShortcutSheet

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
            ForEach(section.entries, id: \.title) { entry in
              GridRow {
                Text(entry.title)
                ShortcutHint(entry.hint)
              }
            }
          }
        }
      }
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

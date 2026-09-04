import SwiftUI
import ThrowntomClient

// MARK: - ShortcutList

/// Every shortcut the app binds, read from the same menu models the menus are built from.
enum ShortcutList {

  // MARK: Internal

  struct Entry: Equatable {
    let title: String
    let hint: String
    /// When this key does something, in words. Static — it is the rule and not this second's
    /// answer — so a reader whose timer is idle still learns what ⌘K is for.
    let condition: String
    /// Whether pressing it would do anything once this sheet is out of the way.
    let isEnabled: Bool
  }

  struct Section: Equatable {
    let name: String
    let entries: [Entry]
  }

  /// The sheet answers two questions, because a reader arrives with both: what the app binds, and
  /// what pressing it right now would do.
  ///
  /// Titles are still taken from no daemon snapshot at all, and that half of the older argument
  /// here stands unchanged: the Timer menu words ⌘R from the owed phase and ⌘⇧P from the current
  /// one, so a sheet taking its words from the snapshot would name a phase out of a daemon the rest
  /// of the window has already given up on — a live report is the one thing this is not, and
  /// `ShortcutSheetTests` pins it.
  ///
  /// Enablement is the half that did not stand. It was withheld for the same reason, but only
  /// because one call produced both: nothing about refusing to name a stale phase requires the list
  /// to claim ⌘R works while a pomodoro is running. It did claim exactly that — every row drawn at
  /// full strength off `state: nil, daemonAvailable: true` — so a list of what EXISTS read as a
  /// list of what WORKS NOW. Each row now carries both answers: live enablement, which the sheet
  /// dims on, and a static condition saying when the row applies, so a dimmed row still teaches.
  ///
  /// All of it is asked of the window *behind* the sheet. `showsShortcuts` is true for as long as
  /// anyone is reading this, and it is what withholds ⌘/ and Confirm; answering for the sheet's own
  /// presence would leave those two rows dim in the only place they are ever seen.
  @MainActor
  static func sections(for environment: AppEnvironment) -> [Section] {
    let daemonAvailable = environment.client.serviceStatus.offersDaemonCommands
    let tasks = MenuModel.tasks(model: environment.model, daemonAvailable: daemonAvailable)
    let app = MenuModel.appConfig()
    return [
      Section(
        name: "Timer",
        entries: entries(
          titles: MenuModel.timer(state: nil, returnIsTaken: false, daemonAvailable: true),
          enablement: MenuModel.timer(
            state: environment.client.state,
            returnIsTaken: environment.returnIsTakenInTheWindow,
            daemonAvailable: daemonAvailable,
          ),
          hint: { $0.shortcutHint },
          condition: { $0.availability },
        ),
      ),
      Section(
        name: "View",
        entries: entries(
          MenuModel.view(showsShortcuts: false, daemonAvailable: daemonAvailable),
          hint: { $0.shortcutHint },
          condition: { $0.availability },
        ) + [escape],
      ),
      Section(name: "Tasks", entries: entries(tasks, hint: { $0.shortcutHint }, condition: { $0.availability })),
      Section(name: "App", entries: entries(app, hint: { $0.shortcutHint }, condition: { $0.availability }) + [quit]),
    ]
  }

  // MARK: Private

  /// Escape, which no menu model owns: the window and this sheet answer it themselves
  /// (`WindowModel.dismiss`), so it binds no key equivalent and would otherwise be the one thing
  /// the app listens for that the list of what the app listens for never mentions. Innermost
  /// first — the duration field, then this sheet, then the panel, then a task edit — which is more
  /// than a column of this width can say, so it says the part a reader needs to press it.
  private static let escape = Entry(
    title: "Dismiss",
    hint: MenuShortcut(key: .escape, modifiers: []).hint,
    condition: "closes what is open",
    isEnabled: true,
  )

  /// Quit is AppKit's own item, so it is the one shortcut no menu model owns.
  private static let quit = Entry(title: "Quit Throwntom", hint: "⌘Q", condition: "", isEnabled: true)

  /// Titles from one menu, enablement from another. They are the same menu everywhere but the
  /// Timer, whose Start and Pause items are worded from the daemon snapshot: the sheet takes those
  /// words from a menu built with no snapshot and only what can fire from the live one. Both menus
  /// list the same items in the same order whatever they are built from, which is what lets the two
  /// be read side by side.
  private static func entries<Action>(
    titles: MenuModel<Action>,
    enablement: MenuModel<Action>,
    hint: (Action) -> String,
    condition: (Action) -> String,
  ) -> [Entry] {
    zip(titles.items, enablement.items).compactMap { titled, live in
      let hint = hint(titled.action)
      return hint.isEmpty
        ? nil
        : Entry(
          title: titled.title,
          hint: hint,
          condition: condition(titled.action),
          isEnabled: live.isEnabled,
        )
    }
  }

  private static func entries<Action>(
    _ menu: MenuModel<Action>,
    hint: (Action) -> String,
    condition: (Action) -> String,
  ) -> [Entry] {
    entries(titles: menu, enablement: menu, hint: hint, condition: condition)
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
              ShortcutRow(entry: entry)
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

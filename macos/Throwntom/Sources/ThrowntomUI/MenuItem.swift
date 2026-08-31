/// One row of a command menu: the verb it runs, how to reach it and whether it can run now.
struct MenuItem<Action: MenuAction>: Identifiable {
  init(action: Action, shortcut: MenuShortcut?, isEnabled: Bool, title: String? = nil) {
    self.action = action
    self.shortcut = shortcut
    self.isEnabled = isEnabled
    self.title = title ?? action.title
  }

  let action: Action
  let shortcut: MenuShortcut?
  let isEnabled: Bool
  /// Usually the action's own title; a toggle verb passes the wording for the current state.
  let title: String

  var id: Action {
    action
  }
}

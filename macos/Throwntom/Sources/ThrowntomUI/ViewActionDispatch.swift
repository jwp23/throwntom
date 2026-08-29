/// Runs a `ViewAction`, so the menu bar and the window's chips do the same thing.
enum ViewActionDispatch {
  @MainActor
  static func show(_ action: ViewAction, in model: WindowModel) {
    switch action {
    case .tasks,
         .stats:
      if let panel = action.panel {
        model.toggle(panel)
      }

    case .shortcuts:
      model.showsShortcuts = true

    case .openConfig:
      ConfigFile.open()
    }
  }
}

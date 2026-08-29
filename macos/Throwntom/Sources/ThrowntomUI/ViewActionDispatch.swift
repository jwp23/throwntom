/// Runs a `ViewAction`, so the menu bar and the window's chips do the same thing.
enum ViewActionDispatch {
  @MainActor
  static func show(_ action: ViewAction, in model: WindowModel) {
    switch action {
    case .tasks:
      model.toggle(.tasks)

    case .stats:
      model.toggle(.stats)

    case .shortcuts:
      model.showsShortcuts = true

    case .openConfig:
      ConfigFile.open()
    }
  }
}

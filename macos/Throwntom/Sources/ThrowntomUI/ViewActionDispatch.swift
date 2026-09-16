import Foundation

/// Runs a `ViewAction`, so the menu bar and the window's chips do the same thing.
enum ViewActionDispatch {
  /// `opener` is passed on to `ConfigFile.open(with:)` and is what makes `.openConfig` safe to
  /// exercise: a caller that hands in its own opener can be driven end to end without a real
  /// editor coming up. Everything else here moves the window's own state and needs no seam.
  @MainActor
  static func show(_ action: ViewAction, in model: WindowModel, opener: (URL) -> Bool = ConfigFile.workspaceOpener) {
    switch action {
    case .tasks:
      model.toggle(.tasks)

    case .stats:
      model.toggle(.stats)

    case .shortcuts:
      model.showsShortcuts = true

    case .openConfig:
      ConfigFile.open(with: opener)
    }
  }
}

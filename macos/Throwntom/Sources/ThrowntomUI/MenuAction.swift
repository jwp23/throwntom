import ThrowntomClient

// MARK: - MenuAction

/// A verb that can appear in a command menu.
protocol MenuAction: Hashable {
  var title: String { get }
}

// MARK: - TimerAction + MenuAction

extension TimerAction: MenuAction { }

// MARK: - TaskAction + MenuAction

extension TaskAction: MenuAction { }

// MARK: - ViewAction + MenuAction

extension ViewAction: MenuAction { }

// MARK: - ServiceAction + MenuAction

extension ServiceAction: MenuAction { }

// MARK: - SnoozeAction + MenuAction

extension SnoozeAction: MenuAction { }

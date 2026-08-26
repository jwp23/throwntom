import Foundation

/// Path segment of POST /v1/timer/{verb}.
public enum TimerVerb: String, Sendable {
    case start, confirm, pause, resume
    case skipToday = "skip-today"
    case newCycle = "new-cycle"
}

/// Timer verbs as the user sees them: title, shortcut hint and the daemon verb behind each.
public enum TimerAction: CaseIterable, Sendable {
    case start, confirm, pause, resume, snooze, skipToday, newCycle

    public var title: String {
        switch self {
        case .start: return "Start"
        case .confirm: return "Confirm"
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .snooze: return "Snooze \(TimerActions.defaultSnoozeMinutes) min"
        case .skipToday: return "Skip Today"
        case .newCycle: return "New Cycle"
        }
    }

    /// Display-only hint; the real key bindings are attached to menu items in the app target.
    public var shortcutHint: String {
        switch self {
        case .start: return "⌘R"
        case .confirm: return "⏎"
        case .pause, .resume: return "⌘P"
        case .snooze: return "⌘⇧S"
        case .skipToday, .newCycle: return ""
        }
    }

    /// nil for snooze, which posts to /v1/timer/snooze with a minutes body instead.
    public var verb: TimerVerb? {
        switch self {
        case .start: return .start
        case .confirm: return .confirm
        case .pause: return .pause
        case .resume: return .resume
        case .skipToday: return .skipToday
        case .newCycle: return .newCycle
        case .snooze: return nil
        }
    }
}

public enum TimerActions {
    public static let defaultSnoozeMinutes = 10

    /// Verbs the daemon would accept in this state, in display order. Mirrors internal/core/commands.go.
    public static func available(for state: DaemonState) -> [TimerAction] {
        switch state.state {
        case .idle:
            return state.morningPending ? [.start, .newCycle, .snooze, .skipToday] : [.start, .newCycle, .skipToday]
        case .work, .shortBreak, .longBreak:
            return [.pause]
        case .paused:
            return [.resume]
        case .awaitingConfirm:
            return [.confirm, .snooze, .newCycle]
        }
    }
}

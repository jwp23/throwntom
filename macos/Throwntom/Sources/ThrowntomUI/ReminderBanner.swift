import Foundation
import ThrowntomClient
import UserNotifications

/// The notification-centre operations a reminder needs, so what the app shows can be worked out
/// without the user's real notification centre, which no test process may reach.
protocol ReminderPresenter {
    /// Attaches Snooze and Confirm to the reminder's category. Without it macOS shows the banner
    /// with no buttons on it and the reminder cannot be answered.
    func registerReminderButtons()
    func postReminder(title: String, body: String) async throws
    func withdrawReminder()
}

/// What a change in the daemon's state means for the reminder banner. Deciding it from the two
/// states rather than from the latest one is what keeps a wait that lasts many frames to one banner.
enum ReminderBanner: Equatable {
    case post(title: String, body: String)
    case withdraw
    /// The banner already matches the daemon and is left as it is.
    case unchanged

    static let title = "Throwntom"

    /// The body when the daemon names no stage to move on to, so the banner never shows a blank line.
    static let unnamedStage = "Ready for the next stage."

    static func decide(from previous: DaemonState?, to current: DaemonState?,
                       authorization: ReminderAuthorization) -> ReminderBanner {
        let waiting = isWaitingForAnAnswer(current)
        guard waiting != isWaitingForAnAnswer(previous) else { return .unchanged }
        guard waiting, let current else { return .withdraw }
        guard authorization.willDeliver else { return .unchanged }
        return .post(title: title, body: current.nextStage?.summary ?? unnamedStage)
    }

    /// Whether the daemon is waiting for the user to answer a reminder. A snooze it has accepted is
    /// an answer: nothing is outstanding again until the snooze runs out.
    private static func isWaitingForAnAnswer(_ state: DaemonState?) -> Bool {
        guard let state else { return false }
        return state.state == .awaitingConfirm && state.snoozeUntil == nil
    }
}

import Foundation
import ThrowntomClient
import UserNotifications

/// The notification-centre operations a reminder needs, so what the app shows can be worked out
/// without the user's real notification centre, which no test process may reach.
protocol ReminderPresenter {
    /// Attaches each reminder's buttons to its category. Without it macOS shows the banner
    /// with no buttons on it and the reminder cannot be answered.
    func registerReminderButtons()
    func postReminder(title: String, body: String) async throws
    func postMorningReminder(title: String, body: String) async throws
    func withdrawReminder()
}

/// What a change in the daemon's state means for the reminder banner. Deciding it from the two
/// states rather than from the latest one is what keeps a wait that lasts many frames to one banner.
enum ReminderBanner: Equatable {
    case post(title: String, body: String)
    /// The morning nudge: idle with nothing running yet, its own title/body and its own actions.
    case postMorning(title: String, body: String)
    case withdraw
    /// The banner already matches the daemon and is left as it is.
    case unchanged

    static let title = "Throwntom"

    /// The body when the daemon names no stage to move on to, so the banner never shows a blank line.
    static let unnamedStage = "Ready for the next stage."

    static let morningBody = "Ready to start your day?"

    /// The two reminders the daemon ever raises. At most one is outstanding at a time: the cycle
    /// reminder only at `awaitingConfirm`, the morning nudge only at `idle`. See ADR-004.
    private enum Waiting: Equatable {
        case cycle
        case morning
    }

    static func decide(from previous: DaemonState?, to current: DaemonState?,
                       authorization: ReminderAuthorization) -> ReminderBanner {
        let previousWaiting = waitingKind(previous)
        guard authorization.willDeliver else {
            return previousWaiting == nil ? .unchanged : .withdraw
        }
        let waiting = waitingKind(current)
        guard waiting != previousWaiting else { return .unchanged }
        guard let waiting, let current else { return .withdraw }
        switch waiting {
        case .cycle:
            return .post(title: title, body: current.nextStage?.summary ?? unnamedStage)
        case .morning:
            return .postMorning(title: title, body: morningBody)
        }
    }

    /// Which reminder, if any, the daemon is waiting for the user to answer. A snooze it has
    /// accepted is an answer: nothing is outstanding again until the snooze runs out.
    private static func waitingKind(_ state: DaemonState?) -> Waiting? {
        guard let state, state.snoozeUntil == nil else { return nil }
        if state.state == .awaitingConfirm { return .cycle }
        if state.state == .idle && state.morningPending { return .morning }
        return nil
    }
}

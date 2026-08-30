import Foundation

// MARK: - ServiceAction

/// The timer service's own lifecycle, as the user sees it. Deliberately apart from `TimerAction`:
/// these do not run the pomodoro, they decide whether anything is running the pomodoro at all.
public enum ServiceAction: CaseIterable, Sendable {
  case start
  case stop

  // MARK: Public

  public var title: String {
    switch self {
    case .start: "Start Timer Service"
    case .stop: "Stop Timer Service"
    }
  }

  /// Stopping the service takes the timer down for every client, so it claims no key equivalent:
  /// a stray keystroke must not be able to end the day's timing.
  public var shortcutHint: String {
    ""
  }
}

// MARK: - ServiceActions

public enum ServiceActions {
  /// The single control the window and the menu bar show. Start is offered exactly when the
  /// daemon is not coming: the user stopped it, launchd refused to launch it, or launchd accepted
  /// and nothing arrived. A running or still-dialling service is on its way to a daemon, so the
  /// useful verb there is Stop.
  ///
  /// The absent situations all resolving to Start is what lets each one's sentence point at this
  /// one control instead of growing a retry button of its own.
  public static func startOrStop(status: ServiceStatus) -> ServiceAction {
    status.offersDaemonCommands ? .stop : .start
  }
}

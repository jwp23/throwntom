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
  /// daemon is not coming: the user stopped it, or launchd refused to launch it. Every other
  /// connection state is on its way to a running daemon, so the useful verb there is Stop.
  ///
  /// A refused launch resolving to Start is what lets the failure note point at this control
  /// instead of growing a retry button of its own.
  public static func startOrStop(
    connection: DaemonClient.Connection,
    registrationFailed: Bool,
  ) -> ServiceAction {
    if connection == .stopped || registrationFailed {
      .start
    } else {
      .stop
    }
  }
}

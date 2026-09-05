import AppKit
import ThrowntomClient

/// Sends a user's action to the daemon and forgets it: the event stream reports the new state,
/// and a refusal (409) or transport failure beeps. Every button, menu and context-menu item goes
/// through here so the rule is written once.
///
/// The beep is what the user gets and stays that way; the log line is what is left to look at
/// afterwards, since a beep says only that something did not happen. The beep is not the chime
/// ADR-009 governs: that one marks a reminder, this one marks a press that did nothing, and the
/// two never sound for the same event.
enum DaemonDispatch {

  // MARK: Internal

  @MainActor
  static func perform(_ action: TimerAction, on client: DaemonClient) {
    Task {
      do {
        try await client.perform(action)
      } catch {
        report("send a timer action", error)
      }
    }
  }

  @MainActor
  static func perform(_ request: SnoozeRequest, on client: DaemonClient) {
    Task {
      do {
        try await client.perform(request)
      } catch {
        report("send a snooze request", error)
      }
    }
  }

  @MainActor
  static func perform(_ request: MeetingRequest, on client: DaemonClient) {
    Task {
      do {
        try await client.perform(request)
      } catch {
        report("send a meeting request", error)
      }
    }
  }

  /// Service lifecycle goes straight to launchd rather than over the socket, so unlike a timer
  /// verb it is synchronous and reports through the client's own error properties.
  @MainActor
  static func control(_ action: ServiceAction, on client: DaemonClient) {
    switch action {
    case .start: client.startService()
    case .stop: client.stopService()
    }
  }

  @MainActor
  static func send(_ line: String, to client: DaemonClient) {
    Task {
      do {
        _ = try await client.command(line)
      } catch {
        // `line` is what the user typed and is deliberately not passed on: the operation names
        // the kind of request, and nothing else about it is recorded.
        report("send a command", error)
      }
    }
  }

  // MARK: Private

  /// What a failed dispatch does: sound, and leave a record of what actually failed. A beep says
  /// only that something did not happen, so on its own it leaves nothing to look at afterwards.
  @MainActor
  private static func report(_ operation: String, _ error: Error) {
    ClientLog.failed(operation, in: .daemon, error: error)
    NSSound.beep()
  }

}

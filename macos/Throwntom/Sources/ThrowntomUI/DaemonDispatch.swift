import AppKit
import ThrowntomClient

/// Sends a user's action to the daemon and forgets it: the event stream reports the new state,
/// and a refusal (409) or transport failure beeps. Every button, menu and context-menu item goes
/// through here so the rule is written once.
enum DaemonDispatch {
  @MainActor
  static func perform(_ action: TimerAction, on client: DaemonClient) {
    Task {
      do { try await client.perform(action) } catch { NSSound.beep() }
    }
  }

  @MainActor
  static func perform(_ action: SnoozeAction, on client: DaemonClient) {
    Task {
      do { try await client.perform(action) } catch { NSSound.beep() }
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
      do { _ = try await client.command(line) } catch { NSSound.beep() }
    }
  }
}

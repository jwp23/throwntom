import SwiftUI
import ThrowntomClient

/// One timer verb as a button; the same control is used in the popover and the task window toolbar.
struct TimerActionButton: View {
    let action: TimerAction
    let client: DaemonClient

    var body: some View {
        Button {
            Task { await perform() }
        } label: {
            HStack {
                Text(action.title)
                if !action.shortcutHint.isEmpty {
                    Spacer()
                    Text(action.shortcutHint).foregroundStyle(.secondary)
                }
            }
        }
        .help(action.shortcutHint.isEmpty ? action.title : "\(action.title) (\(action.shortcutHint))")
    }

    private func perform() async {
        do {
            if let verb = action.verb {
                try await client.timer(verb)
            } else {
                try await client.snooze(minutes: TimerActions.defaultSnoozeMinutes)
            }
        } catch {
            NSSound.beep()
        }
    }
}

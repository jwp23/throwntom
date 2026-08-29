import Foundation
import ThrowntomClient

// MARK: - MascotGlyph

/// What sits in the mascot slot until the mascot does: an emoji, or an SF Symbol name where no emoji renders reliably.
enum MascotGlyph: Equatable {
  case emoji(String)
  case symbol(String)
}

// MARK: - MainWindowContent

/// Everything the window shows for one snapshot of daemon, connection and panel state. Deciding it here
/// keeps the phase, countdown and chip rules out of the SwiftUI bodies and under unit test.
struct MainWindowContent: Equatable {

  // MARK: Lifecycle

  init(
    state: DaemonState?,
    connection: DaemonClient.Connection,
    tasks: TaskList,
    error: String?,
    panel: WindowPanel?,
    now: Date,
  ) {
    scheme = Palette.scheme(for: state?.state)
    glyph = Self.glyph(for: state?.state)
    title = state?.state.displayName ?? ConnectionStatus.placeholderText(state: nil, connection: connection, now: now) ?? ""
    countdown = state.flatMap { Self.countdown(for: $0, now: now) }
    nextStage = state?.nextStage.map { "Next: \($0.summary)" }
    garden = state
      .map { TomatoGarden(completedToday: $0.completedToday, inBlock: $0.workSessionsInBlock, every: $0.longBreakEvery) }
    chips = state.map(TimerActions.available(for:)) ?? []
    primaryChip = [TimerAction.confirm, .start, .resume].first(where: chips.contains)
    focused = state.map { tasks.focused(ids: $0.focusedTaskIds) } ?? []
    self.error = error
    self.panel = panel
    pulses = state?.state == .awaitingConfirm
  }

  // MARK: Internal

  let scheme: PhaseScheme
  let glyph: MascotGlyph
  let title: String
  let countdown: String?
  let nextStage: String?
  let garden: TomatoGarden?
  let chips: [TimerAction]
  let primaryChip: TimerAction?
  let focused: [TaskItem]
  let error: String?
  let panel: WindowPanel?
  let pulses: Bool

  // MARK: Private

  private static func glyph(for phase: DaemonState.Phase?) -> MascotGlyph {
    switch phase {
    case .work: .emoji("🍅")
    case .shortBreak: .emoji("☕")
    case .longBreak: .emoji("🌿")
    case .idle: .emoji("🌱")
    case .awaitingConfirm: .emoji("🔔")
    case .paused: .symbol("pause.fill")
    case nil: .symbol("bolt.horizontal.circle")
    }
  }

  private static func countdown(for state: DaemonState, now: Date) -> String? {
    switch state.state {
    case .work,
         .shortBreak,
         .longBreak:
      state.phaseEndAt.map { Countdown.formatRemaining($0.timeIntervalSince(now)) }
    case .paused:
      Countdown.formatRemaining(TimeInterval(state.pausedRemaining))
    case .idle,
         .awaitingConfirm:
      nil
    }
  }

}

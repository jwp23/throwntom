import SwiftUI

/// The mascot over the phase name, countdown and next stage — the part of the window that reads
/// from across the room.
struct TimerHeader: View {
  static let mascotSize: CGFloat = 200

  /// How many lines the phase name may take: as many as it needs. At the window's 320pt minimum
  /// the longest titles — `Pomodoro (reconnecting)`, `Done for today (reconnecting)`,
  /// `Timer service isn’t answering` — already need both lines of a two-line budget at the default
  /// text size, and four at twice that size, so any fixed cap has no headroom for a longer phase
  /// name, a reworded wait, a translation or an enlarged text size. The title is what the window is
  /// read for from across the room, so it is the last thing that may be cut off (throwntom-2jq).
  /// Nothing else in the window carries a line limit; notes, hints and chip rows wrap or flow.
  ///
  /// Unbounded is safe because the title is a closed set of short phrases —
  /// `MainWindowContent.phaseTitle` or `ConnectionStatus.text`, never task text or a daemon
  /// sentence. `TimerHeaderTests` measures every one of them.
  static let titleLineLimit: Int? = nil

  let content: MainWindowContent

  var body: some View {
    VStack(spacing: 8) {
      MascotView(pose: content.pose, scheme: content.scheme)
        .frame(maxWidth: Self.mascotSize)
      VStack(spacing: 2) {
        Text(content.title)
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .lineLimit(Self.titleLineLimit)
          .fixedSize(horizontal: false, vertical: true)
        if let countdown = content.countdown {
          Text(countdown).font(.title2).monospacedDigit()
        }
        if let next = content.nextStage {
          Text(next).font(.body)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }
}

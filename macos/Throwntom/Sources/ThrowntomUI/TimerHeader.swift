import SwiftUI

/// The mascot over the phase name, countdown and next stage — the part of the window that reads
/// from across the room.
struct TimerHeader: View {
  static let mascotSize: CGFloat = 200

  /// How many lines the phase name may take: as many as it needs. A fixed budget of two was
  /// exactly consumed at the default text size — `Pomodoro (reconnecting)` and
  /// `Timer service isn’t answering` each filled both lines at the window's 320pt minimum — so
  /// every enlargement truncated the title, and the one thing the window is read for from across
  /// the room was the one thing in it that could not wrap (throwntom-2jq). Nothing else in the
  /// window carries a line limit; notes, hints and chip rows all wrap or flow instead.
  ///
  /// Unbounded is safe here because the title is a closed set of short phrases —
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

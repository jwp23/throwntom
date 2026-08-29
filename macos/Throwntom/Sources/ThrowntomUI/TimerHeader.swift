import SwiftUI

/// The mascot over the phase name, countdown and next stage — the part of the window that reads
/// from across the room.
struct TimerHeader: View {
  static let mascotSize: CGFloat = 200

  let content: MainWindowContent

  var body: some View {
    VStack(spacing: 8) {
      MascotView(pose: content.pose, scheme: content.scheme)
        .frame(maxWidth: Self.mascotSize)
      VStack(spacing: 2) {
        Text(content.title)
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .lineLimit(2)
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

import SwiftUI

/// Slot, phase name, countdown and the next stage — the part of the window that reads from across the room.
struct TimerHeader: View {
  let content: MainWindowContent

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      MascotSlot(glyph: content.glyph, scheme: content.scheme)
      VStack(alignment: .leading, spacing: 2) {
        Text(content.title)
          .font(.largeTitle.weight(.bold))
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
  }
}

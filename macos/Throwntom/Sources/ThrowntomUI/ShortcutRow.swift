import SwiftUI

/// One line of the cheat sheet: what the command is called, the keys, and when they apply.
///
/// Dimmed while the command cannot fire. `DESIGN.md` forbids dimming a shortcut everywhere else and
/// records this as its one exception: elsewhere a hint sits beside the control it describes, which
/// is already drawn disabled, but the sheet is a page of shortcuts with no controls on it, so
/// without the dim the only signal left is the condition text — and reading fifteen conditions
/// against the timer's current phase is work the sheet exists to save.
///
/// The condition stays for the same reason it was added: a dim on its own says "not now" and never
/// says when — so, unlike the title and the hint, it draws at the same weight whatever the row's
/// own state is, quieter than the title so it reads as a footnote rather than a third title, but
/// never quieter than that: `.foregroundStyle(.secondary)` was the first attempt, and it fails —
/// `NSColor.secondaryLabelColor` composited with `unavailableOpacity` on an already-dimmed row
/// lands at 1.96:1 on the light appearance, well under the 4.5:1 floor `ShortcutRowTests` holds
/// every line in this sheet to. `unavailableOpacity` alone, with nothing stacked on it, is the one
/// value already proven to clear that floor on both appearances, so the condition column is held
/// at exactly that opacity, once, rather than composed with the row's own dim.
struct ShortcutRow: View {

  /// What an unavailable row's title and hint are drawn at, and what the condition column is
  /// always drawn at. The lowest opacity that still clears 4.5:1 on both appearances, so a dimmed
  /// row is quieter than its neighbours without dropping below the contrast every other line in
  /// the app is held to — `ShortcutRowTests` holds it there.
  static let unavailableOpacity = 0.55

  let entry: ShortcutList.Entry

  /// What the first cell says aloud. The dim is the row's whole answer to "can I press this now",
  /// and it is only drawn, so a reader who cannot see it would be told nothing — the same reason a
  /// task row says "focused" in words. It rides on the title rather than on the row because a
  /// modifier put on a `GridRow` lands on each of its cells, which would say this three times.
  var spokenTitle: String {
    entry.isEnabled ? entry.title : "\(entry.title), unavailable"
  }

  var body: some View {
    GridRow {
      Text(entry.title)
        .accessibilityLabel(spokenTitle)
        .opacity(entry.isEnabled ? 1 : Self.unavailableOpacity)
      ShortcutHint(entry.hint)
        .opacity(entry.isEnabled ? 1 : Self.unavailableOpacity)
      Text(entry.condition)
        .opacity(Self.unavailableOpacity)
    }
  }

}

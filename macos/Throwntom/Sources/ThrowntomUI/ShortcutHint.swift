import SwiftUI

/// A keyboard hint under a panel or in the cheat sheet. Body-sized monospaced at medium weight in
/// the panel's own text colour — it carries no dimming of its own, because the shortcut is the part
/// a new user came to read — and it wraps rather than truncating on a narrow window.
///
/// A cheat-sheet row dims as a whole while its command cannot fire (`ShortcutRow`), which is the
/// one exception `DESIGN.md` records; nothing is done to the hint here to bring that about, and
/// nowhere else does a hint lose contrast.
struct ShortcutHint: View {

  // MARK: Lifecycle

  init(_ text: String) {
    self.text = text
  }

  // MARK: Internal

  static let font = Font.body.monospaced().weight(.medium)

  let text: String

  var body: some View {
    Text(text)
      .font(Self.font)
      .fixedSize(horizontal: false, vertical: true)
  }

}

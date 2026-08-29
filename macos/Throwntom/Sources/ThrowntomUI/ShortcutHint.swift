import SwiftUI

/// A keyboard hint under a panel or in the cheat sheet. Body-sized monospaced at medium weight in
/// the panel's own text colour — never dimmed, because the shortcut is the part a new user came to
/// read — and it wraps rather than truncating on a narrow window.
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

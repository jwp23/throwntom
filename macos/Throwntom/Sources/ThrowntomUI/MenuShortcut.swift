import SwiftUI

/// The key binding of a menu item. Separate from the item so items without one are expressible.
struct MenuShortcut: Hashable {

  // MARK: Internal

  let key: KeyEquivalent
  let modifiers: EventModifiers

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(key, modifiers: modifiers)
  }

  /// The canonical way to write this binding: the modifier glyphs in the order this app writes them
  /// (⌘ before ⇧), then the key. Each action still carries its own `shortcutHint` for display, since
  /// those live in `ThrowntomClient` and cannot reach this type; `MenuBindingTests` holds every one
  /// of them to this rendering, so a rebinding cannot leave the UI advertising the old key.
  var hint: String {
    var glyphs = ""
    if modifiers.contains(.command) {
      glyphs += "⌘"
    }
    if modifiers.contains(.shift) {
      glyphs += "⇧"
    }
    if modifiers.contains(.option) {
      glyphs += "⌥"
    }
    if modifiers.contains(.control) {
      glyphs += "⌃"
    }
    return glyphs + Self.glyph(for: key)
  }

  static func ==(lhs: MenuShortcut, rhs: MenuShortcut) -> Bool {
    lhs.key.character == rhs.key.character && lhs.modifiers == rhs.modifiers
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(key.character)
    hasher.combine(modifiers.rawValue)
  }

  // MARK: Private

  /// The keys that print as a symbol rather than as themselves.
  private static func glyph(for key: KeyEquivalent) -> String {
    switch key.character {
    case KeyEquivalent.return.character: "⏎"
    case KeyEquivalent.delete.character: "⌫"
    case KeyEquivalent.upArrow.character: "↑"
    case KeyEquivalent.downArrow.character: "↓"
    default: String(key.character).uppercased()
    }
  }

}

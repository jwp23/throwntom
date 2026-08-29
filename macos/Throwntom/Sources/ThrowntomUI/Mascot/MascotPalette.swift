import SwiftUI

/// The mascot's own paint, documented as the `mascot-*` tokens in DESIGN.md and used nowhere else.
enum MascotPalette {
  static let bodyLight = HexColor("#FF6A55")
  static let body = HexColor("#E23A2E")
  static let bodyDark = HexColor("#9E1E18")
  static let leafLight = HexColor("#7CC04A")
  static let leafDark = HexColor("#2E7A1E")
  static let blush = HexColor("#F27C9A")
  static let propLight = HexColor("#8A8A8E")
  static let propDark = HexColor("#3A3A3E")
  static let wood = HexColor("#B8642A")
  static let sky = HexColor("#9ED8F5")

  /// Every token with its DESIGN.md name, in the order the front matter lists them.
  static let tokens: [(name: String, color: HexColor)] = [
    ("mascot-body-light", bodyLight),
    ("mascot-body", body),
    ("mascot-body-dark", bodyDark),
    ("mascot-leaf-light", leafLight),
    ("mascot-leaf-dark", leafDark),
    ("mascot-blush", blush),
    ("mascot-prop-light", propLight),
    ("mascot-prop-dark", propDark),
    ("mascot-wood", wood),
    ("mascot-sky", sky),
  ]
}

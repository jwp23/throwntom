import SwiftUI
import ThrowntomClient

// MARK: - HexColor

/// A colour that is testable as a number and drawable as SwiftUI `Color`.
struct HexColor: Equatable, Sendable {
  init(_ hex: String) {
    self.hex = hex
  }

  let hex: String

  var color: Color {
    Color(.sRGB, red: channel(0), green: channel(1), blue: channel(2), opacity: 1)
  }

  /// 0…1 for the red, green or blue byte of `#RRGGBB`.
  func channel(_ index: Int) -> Double {
    let start = hex.index(hex.startIndex, offsetBy: 1 + index * 2)
    let byte = UInt8(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16) ?? 0
    return Double(byte) / 255
  }
}

extension HexColor {
  /// The same hue under `fraction` of black: every channel scaled by `1 - fraction`.
  func darkened(by fraction: Double) -> HexColor {
    let bytes = (0 ..< 3).map { Int((channel($0) * 255 * (1 - fraction)).rounded()) }
    return HexColor(String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2]))
  }
}

// MARK: - PhaseScheme

/// The colours of the window in one phase. Text is the dark ink on every phase ground; cream is
/// reserved for the primary chip's label, where it sits on the outline brown.
struct PhaseScheme: Equatable, Sendable {
  let ground: HexColor
  let text: HexColor
  let primaryChip: HexColor
  let primaryChipText: HexColor
  let secondaryChip: HexColor
  let secondaryChipText: HexColor
  /// The ground under 28% black, precomputed so panel text can be contrast-tested.
  let panel: HexColor
  /// The panel's text colour: cream on every scheme.
  let panelText: HexColor
}

/// The mark at the head of a task — a filled star when it is focused, an open circle when it is
/// not — takes the colour of whatever surface it sits on rather than a tint of its own. These are
/// the values `PaletteTests` holds to 4.5:1 on the ground and on the panel, and a mark is read
/// like the words beside it. `Color.yellow`, which the star used to carry, never went through
/// that gate: it lands at 1.8:1 on the idle ground and changes with the system appearance, where
/// the rest of the window looks the same in both. Nothing is lost by dropping it — the two glyphs
/// differ in shape, and a row says "focused" aloud (`TaskRow.label`).
extension PhaseScheme {
  var taskMark: HexColor {
    text
  }

  var panelTaskMark: HexColor {
    panelText
  }
}

/// The sofa the mascot reads on during a long break is upholstered in the phase's own tones so it
/// belongs to the room rather than importing a wood colour.
extension PhaseScheme {
  var sofaBack: HexColor {
    panel
  }

  var sofaArm: HexColor {
    ground.darkened(by: 0.19)
  }

  var sofaSeat: HexColor {
    ground.darkened(by: 0.10)
  }
}

// MARK: - Palette

enum Palette {

  // MARK: Internal

  static let ink = HexColor("#1F130C")
  static let cream = HexColor("#FFF6EA")
  static let outline = HexColor("#2B1A10")
  static let white = HexColor("#FFFFFF")

  /// Every scheme with the DESIGN.md token name of its ground, in display order.
  static let schemes: [(name: String, scheme: PhaseScheme)] = [
    ("macos-work", scheme(for: .work)),
    ("macos-short-break", scheme(for: .shortBreak)),
    ("macos-long-break", scheme(for: .longBreak)),
    ("macos-idle", scheme(for: .idle)),
    ("macos-paused", scheme(for: .paused)),
    ("macos-awaiting-confirm", scheme(for: .awaitingConfirm)),
    ("macos-disconnected", scheme(for: nil)),
  ]

  static func scheme(for phase: DaemonState.Phase?) -> PhaseScheme {
    switch phase {
    case .work: jewel(ground: "#D9651A", secondaryChip: "#622D0C", panel: "#9C4913")
    case .shortBreak: jewel(ground: "#1E9AA3", secondaryChip: "#0D4549", panel: "#166F75")
    case .longBreak: jewel(ground: "#5A8CE0", secondaryChip: "#283F65", panel: "#4165A1")
    case .idle: jewel(ground: "#B8961F", secondaryChip: "#53440E", panel: "#846C16")
    case .paused: jewel(ground: "#8A8A8E", secondaryChip: "#3E3E40", panel: "#636366")
    case .awaitingConfirm: jewel(ground: "#E8583A", secondaryChip: "#68281A", panel: "#A73F2A")
    case nil:
      // No timer verbs show without a phase, so the service chip carries whatever weight this
      // ground has — primary while it reads Start (stopped or refused), secondary while it reads
      // Stop (on its way up: `ServiceActions.startOrStop`). Both share the cream/outline pairing
      // so it reads right either way.
      PhaseScheme(
        ground: HexColor("#3A2A22"),
        text: cream,
        primaryChip: cream,
        primaryChipText: outline,
        secondaryChip: cream,
        secondaryChipText: outline,
        panel: HexColor("#2A1E18"),
        panelText: cream,
      )
    }
  }

  // MARK: Private

  /// The secondary chip is the ground under 55% black, the panel the ground under 28% black,
  /// both precomputed so they can be contrast-tested.
  private static func jewel(ground: String, secondaryChip: String, panel: String) -> PhaseScheme {
    PhaseScheme(
      ground: HexColor(ground),
      text: ink,
      primaryChip: outline,
      primaryChipText: cream,
      secondaryChip: HexColor(secondaryChip),
      secondaryChipText: white,
      panel: HexColor(panel),
      panelText: cream,
    )
  }

}

// MARK: - Contrast

/// WCAG 2 contrast ratio, the same arithmetic as the Go palette test in `cmd/throwntom/theme_test.go`.
enum Contrast {
  static func ratio(_ a: HexColor, _ b: HexColor) -> Double {
    let la = luminance(a)
    let lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  private static func luminance(_ c: HexColor) -> Double {
    func linear(_ v: Double) -> Double {
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(c.channel(0)) + 0.7152 * linear(c.channel(1)) + 0.0722 * linear(c.channel(2))
  }
}

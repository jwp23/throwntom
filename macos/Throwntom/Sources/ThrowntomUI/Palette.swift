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

// MARK: - PhaseScheme

/// The colours of the window in one phase. Text is the dark ink on every phase ground; cream is
/// reserved for the mascot slot and the primary chip's label, where it sits on the outline brown.
struct PhaseScheme: Equatable, Sendable {
  let ground: HexColor
  let text: HexColor
  let primaryChip: HexColor
  let primaryChipText: HexColor
  let secondaryChip: HexColor
  let secondaryChipText: HexColor
  let slot: HexColor
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
    case .work: jewel(ground: "#D9651A", secondaryChip: "#622D0C")
    case .shortBreak: jewel(ground: "#1E9AA3", secondaryChip: "#0D4549")
    case .longBreak: jewel(ground: "#5A8CE0", secondaryChip: "#283F65")
    case .idle: jewel(ground: "#B8961F", secondaryChip: "#53440E")
    case .paused: jewel(ground: "#8A8A8E", secondaryChip: "#3E3E40")
    case .awaitingConfirm: jewel(ground: "#E8583A", secondaryChip: "#68281A")
    case nil:
      // Disconnected state renders no chips; both primary and secondary share the cream/outline pairing.
      PhaseScheme(
        ground: HexColor("#3A2A22"),
        text: cream,
        primaryChip: cream,
        primaryChipText: outline,
        secondaryChip: cream,
        secondaryChipText: outline,
        slot: cream,
      )
    }
  }

  // MARK: Private

  /// The secondary chip is the ground under 55% black, precomputed so it can be contrast-tested.
  private static func jewel(ground: String, secondaryChip: String) -> PhaseScheme {
    PhaseScheme(
      ground: HexColor(ground),
      text: ink,
      primaryChip: outline,
      primaryChipText: cream,
      secondaryChip: HexColor(secondaryChip),
      secondaryChipText: white,
      slot: cream,
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

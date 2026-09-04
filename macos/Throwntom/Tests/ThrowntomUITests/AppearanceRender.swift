import AppKit
import SwiftUI
import XCTest
@testable import ThrowntomUI

// MARK: - AppearanceRender

/// Draws a view offscreen under a named system appearance, so a test can assert the colour that
/// would actually be painted rather than the one the source declares. Reading the source is not
/// enough for these: a control that AppKit draws takes the *system's* colours whatever the view
/// asked for, which is the whole shape of the snooze bugs.
///
/// `ImageRenderer` paints SwiftUI's own drawing and nothing else — a control backed by AppKit comes
/// back as SwiftUI's unrenderable placeholder (flat yellow, red hatching) instead of its chrome. That
/// is not a limitation to work around here; it is the signal. A surface that renders as its own
/// palette is a surface SwiftUI drew and the system appearance cannot reach.
///
/// Which of the two knobs below carries the coverage was measured, because they do not both work.
/// Varying `scheme` alone changes what comes out of the renderer; varying `appearance` alone
/// changes nothing — not for a system colour, and not for an AppKit-drawn control, which renders
/// as the placeholder under either. `ImageRenderer` reads SwiftUI's environment and not
/// `NSAppearance.currentDrawingAppearance`, so `colorScheme` is the axis a test here is actually
/// sweeping, and `AppearanceRenderTests` is the negative control that keeps that true. The
/// appearance is still set, because it costs nothing and is what the AppKit half would read if a
/// future renderer ever drew it; nothing should be claimed on its behalf until it does.
@MainActor
enum AppearanceRender {

  // MARK: Internal

  /// Both system appearances, so a surface can be asserted to look the same in either.
  static let appearances: [(name: String, appearance: NSAppearance.Name, scheme: ColorScheme)] = [
    ("light", .aqua, .light),
    ("dark", .darkAqua, .dark),
  ]

  /// The pixels of `view`, drawn as the given appearance.
  static func bitmap(
    _ view: some View,
    appearance: NSAppearance.Name,
    scheme: ColorScheme,
  ) throws -> NSBitmapImageRep {
    var rendered: NSBitmapImageRep?
    NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
      let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
      renderer.scale = 1
      rendered = renderer.nsImage
        .flatMap(\.tiffRepresentation)
        .flatMap(NSBitmapImageRep.init(data:))
    }
    return try XCTUnwrap(rendered, "nothing rendered")
  }

  /// A drawing as PNG bytes, which is how two of them are compared pixel for pixel.
  static func png(_ rep: NSBitmapImageRep) throws -> Data {
    try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }

  /// How much of the drawing is exactly `hex`. Zero says the colour was never painted.
  static func pixels(of hex: String, in rep: NSBitmapImageRep) -> Int {
    var count = 0
    for y in 0 ..< rep.pixelsHigh {
      for x in 0 ..< rep.pixelsWide where self.hex(rep.colorAt(x: x, y: y)) == hex {
        count += 1
      }
    }
    return count
  }

  /// What `colour` looks like on the way out of the renderer. `ImageRenderer` hands back its own
  /// colour space, so a token's hex is not the hex that comes back; a swatch through the same path
  /// is the only honest thing to compare a pixel against.
  static func swatch(
    _ colour: HexColor,
    appearance: NSAppearance.Name,
    scheme: ColorScheme,
  ) throws -> String {
    let rep = try bitmap(
      Rectangle().fill(colour.color).frame(width: 8, height: 8),
      appearance: appearance,
      scheme: scheme,
    )
    return hex(rep.colorAt(x: 4, y: 4))
  }

  /// The size the view lays itself out at, which is how a text style's size is measured: `.body`
  /// draws taller than `.caption` and there is no other way to read a font back off a built view.
  static func size(_ view: some View) throws -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    return try XCTUnwrap(renderer.nsImage).size
  }

  /// A piece of the window as the window draws it: on the phase's ground, in the phase's text
  /// colour, in a fixed box so two of them can be compared pixel for pixel.
  static func onGround(_ view: some View, scheme: PhaseScheme, width: CGFloat, height: CGFloat) -> some View {
    view
      .frame(width: width, height: height)
      .background(scheme.ground.color)
      .foregroundStyle(scheme.text.color)
  }

  // MARK: Private

  private static func hex(_ colour: NSColor?) -> String {
    guard let colour = colour?.usingColorSpace(.sRGB) else { return "none" }
    return String(
      format: "#%02X%02X%02X",
      Int((colour.redComponent * 255).rounded()),
      Int((colour.greenComponent * 255).rounded()),
      Int((colour.blueComponent * 255).rounded()),
    )
  }

}

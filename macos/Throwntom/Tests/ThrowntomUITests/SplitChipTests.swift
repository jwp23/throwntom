import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

@MainActor
final class SplitChipTests: XCTestCase {

  /// The chip has to look like a chip before anything else — the same fill and text colours
  /// every plain chip wears, painted by SwiftUI itself rather than by an AppKit control's own
  /// tinting (throwntom-bxd.2, throwntom-bxd.29).
  func testTheChipPaintsTheStylesFillAndTextColours() throws {
    let scheme = Palette.scheme(for: .idle)
    let style = ChipStyle.style(primary: false, scheme: scheme)
    let menu = MenuModel.snooze(canDefer: true, isSnoozed: false)
    let chip = SplitChip(title: "Snooze", hint: "", style: style, menu: menu, primaryAction: { }) { item in
      Button(item.title) { }.disabled(!item.isEnabled)
    }
    for appearance in AppearanceRender.appearances {
      let drawn = try AppearanceRender.bitmap(
        AppearanceRender.onGround(chip, scheme: scheme, width: 200, height: 44),
        appearance: appearance.appearance,
        scheme: appearance.scheme,
      )
      let fill = try AppearanceRender.swatch(style.fill, appearance: appearance.appearance, scheme: appearance.scheme)
      let text = try AppearanceRender.swatch(style.text, appearance: appearance.appearance, scheme: appearance.scheme)
      XCTAssertGreaterThan(AppearanceRender.pixels(of: fill, in: drawn), 500, appearance.name)
      XCTAssertGreaterThan(AppearanceRender.pixels(of: text, in: drawn), 0, appearance.name)
    }
  }

  /// A chevron region wide enough to click is a second glyph the layout has to make room for,
  /// so the split chip has to lay out wider than the same label alone — the same width-diff
  /// technique `ChipTests` used to prove the old decorative chevron rendered.
  func testTheChipLaysOutWiderThanAPlainLabelForTheChevronRegion() throws {
    let scheme = Palette.scheme(for: .idle)
    let style = ChipStyle.style(primary: false, scheme: scheme)
    let menu = MenuModel.snooze(canDefer: true, isSnoozed: false)
    let plainSize = try AppearanceRender.size(ChipLabel(title: "Snooze", hint: "", style: style))
    let chip = SplitChip(title: "Snooze", hint: "", style: style, menu: menu, primaryAction: { }) { item in
      Button(item.title) { }.disabled(!item.isEnabled)
    }
    let splitSize = try AppearanceRender.size(chip)
    XCTAssertGreaterThan(splitSize.width, plainSize.width)
  }

  /// No divider marks the seam between the label and the chevron — the whole chip reads as
  /// one control, the way DESIGN.md's Chip (macOS) section describes it. The same
  /// type-description technique `ChipTests.testTimerChipsFlowRatherThanSitInOneStack` uses
  /// to prove a view IS in the tree proves the inverse here — that `Divider` is not.
  func testTheChipDrawsNoDividerBetweenTheTwoRegions() {
    let scheme = Palette.scheme(for: .idle)
    let style = ChipStyle.style(primary: false, scheme: scheme)
    let menu = MenuModel.snooze(canDefer: true, isSnoozed: false)
    let chip = SplitChip(title: "Snooze", hint: "", style: style, menu: menu, primaryAction: { }) { item in
      Button(item.title) { }.disabled(!item.isEnabled)
    }
    let bodyType = String(describing: type(of: chip.body))
    XCTAssertFalse(bodyType.contains("Divider"), bodyType)
  }

}

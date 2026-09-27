import AppKit
import SwiftUI
import XCTest
@testable import ThrowntomUI

// MARK: - BlockFlowLayoutTests

@MainActor
final class BlockFlowLayoutTests: XCTestCase {
  func testAllBlocksFitOnOneRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 400, gap: 12), [[0, 1, 2]])
  }

  func testTwoBlocksFitAndTheThirdWraps() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 180, gap: 12), [[0, 1], [2]])
  }

  func testOnlyOneBlockFitsPerRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 100, gap: 12), [[0], [1], [2]])
  }

  func testNeverFewerThanOnePerRow() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [80, 80, 80], available: 10, gap: 12), [[0], [1], [2]])
  }

  /// The wrap decision adds `leadingGap` to the row so far; a mutant that subtracted it instead
  /// would let this pair share a row (50 - 10 + 45 = 85, under 100) instead of wrapping.
  func testWrapDecisionAddsTheLeadingGapToTheRunningWidth() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [50, 45], available: 100, gap: 10), [[0], [1]])
  }

  /// A row exactly as wide as `available` must not wrap: the comparison is strictly `>`. A
  /// mutant weakening it to `>=` would wrap this exact-fit pair (50 + 0 + 50 = 100 >= 100).
  func testFitsExactlyToAvailableWidthWithoutWrapping() {
    XCTAssertEqual(BlockFlowLayout.rowBreaks(widths: [50, 50], available: 100, gap: 0), [[0, 1]])
  }

  func testRowOriginCentresANarrowRow() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
    XCTAssertEqual(BlockFlowLayout.rowOrigin(bounds: bounds, rowWidth: 100), 150)
  }

  func testRowOriginLeavesAFullWidthRowAtTheEdge() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 100)
    XCTAssertEqual(BlockFlowLayout.rowOrigin(bounds: bounds, rowWidth: 400), 0)
  }

  /// `sizeThatFits`'s height sums each row's own height, then adds `rowSpacing` once per gap
  /// between rows (`rows.count - 1` gaps, never negative). Two rows of height 30 and 15 with a
  /// 5pt row spacing must report exactly 50 -- any of the four arithmetic operators in that
  /// formula (the two `+`, the `-` inside `max`, and the `*`) landing on the wrong operator
  /// produces a different, uniquely wrong number (-40, 40, 60, or 45.2).
  func testHeightSumsRowHeightsPlusSpacingBetweenRows() {
    let host = NSHostingView(rootView: flowHostSize(
      sizes: [CGSize(width: 80, height: 20), CGSize(width: 80, height: 30), CGSize(width: 80, height: 15)],
      gap: 10,
      rowSpacing: 5,
      containerWidth: 200,
    ))
    XCTAssertEqual(host.fittingSize.height, 50, accuracy: 0.001)
  }

  /// `placeSubviews` centres each row via `rowOrigin(bounds:rowWidth:)` and stacks rows by
  /// `row.height + rowSpacing`. Four blocks in a 200pt-wide container wrap after three
  /// (40 + 50 + 60 + 2*10 = 170 fits, +70 more does not), so this exercises both a three-item
  /// row (needed to tell the gap-side ternary in `rows(for:)` apart from its `!=` mutant -- a
  /// two-item row cannot, since swapping which single item earns the gap leaves the same total)
  /// and the row-to-row y advance, and confirms every block actually got placed at all.
  func testPlacesRowsCentredHorizontallyAndStackedVertically() throws {
    let capture = FrameCapture()
    let host = NSHostingView(rootView: flowHost(
      sizes: [
        CGSize(width: 40, height: 20),
        CGSize(width: 50, height: 30),
        CGSize(width: 60, height: 25),
        CGSize(width: 70, height: 15),
      ],
      gap: 10,
      rowSpacing: 5,
      capture: capture,
    ))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
    host.layoutSubtreeIfNeeded()
    host.layoutSubtreeIfNeeded()

    XCTAssertEqual(capture.frames.count, 4, "every block must be placed")
    XCTAssertEqual(try XCTUnwrap(capture.frames[0]).origin, CGPoint(x: 15, y: 0))
    XCTAssertEqual(try XCTUnwrap(capture.frames[1]).origin, CGPoint(x: 65, y: 0))
    XCTAssertEqual(try XCTUnwrap(capture.frames[2]).origin, CGPoint(x: 125, y: 0))
    XCTAssertEqual(try XCTUnwrap(capture.frames[3]).origin, CGPoint(x: 65, y: 35))
  }
}

// MARK: - FramePreferenceKey

/// Collects each measured block's frame in the layout's own coordinate space, keyed by index.
private struct FramePreferenceKey: PreferenceKey {
  static let defaultValue = [Int: CGRect]()

  static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
    value.merge(nextValue()) { _, new in new }
  }
}

// MARK: - FrameCapture

/// Where `onPreferenceChange`'s captured frames land, read back after forcing layout.
@MainActor
private final class FrameCapture {
  var frames = [Int: CGRect]()
}

/// Hosts `BlockFlowLayout` around fixed-size blocks and records where each one actually lands,
/// so `placeSubviews` and `sizeThatFits` can be exercised the same way the real chip rows are --
/// through SwiftUI's own layout pass, not by calling the private, `Subviews`-shaped helpers.
@MainActor
private func flowHost(sizes: [CGSize], gap: CGFloat, rowSpacing: CGFloat, capture: FrameCapture) -> some View {
  BlockFlowLayout(blockGap: gap, rowSpacing: rowSpacing) {
    ForEach(Array(sizes.enumerated()), id: \.offset) { index, size in
      Color.clear
        .frame(width: size.width, height: size.height)
        .background(GeometryReader { geometry in
          Color.clear.preference(key: FramePreferenceKey.self, value: [index: geometry.frame(in: .named("flow"))])
        })
    }
  }
  .coordinateSpace(name: "flow")
  .onPreferenceChange(FramePreferenceKey.self) { frames in capture.frames = frames }
}

/// Hosts `BlockFlowLayout` at a fixed container width, so `NSHostingView.fittingSize` reports
/// the height `sizeThatFits(proposal:subviews:cache:)` computes for it -- driven the same way
/// any real parent view would drive it, rather than calling that private-shaped method directly.
@MainActor
private func flowHostSize(sizes: [CGSize], gap: CGFloat, rowSpacing: CGFloat, containerWidth: CGFloat) -> some View {
  BlockFlowLayout(blockGap: gap, rowSpacing: rowSpacing) {
    ForEach(Array(sizes.enumerated()), id: \.offset) { _, size in
      Color.clear.frame(width: size.width, height: size.height)
    }
  }
  .frame(width: containerWidth)
}

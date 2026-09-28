import AppKit
import ObjectiveC
import SwiftUI
import XCTest

/// The trace is only worth attaching to a failure if it records what a render did to a text field,
/// and it is only safe to open inside a test if AppKit is exactly as it was once the trace closes.
@MainActor
final class TextFieldSizingTraceTests: XCTestCase {

  // MARK: Internal

  func testARenderedFieldsFontAndItsMeasurementAreRecorded() throws {
    let traced = try TextFieldSizingTrace.record {
      try AppearanceRender.size(TextField("minutes", text: .constant("")).font(.caption))
    }

    XCTAssertTrue(traced.calls.contains { $0.hasPrefix("init ") }, traced.calls.description)
    XCTAssertTrue(traced.calls.contains { $0.hasPrefix("setFont ") && $0.hasSuffix(" 10.0") }, traced.calls.description)
    XCTAssertTrue(traced.calls.contains { $0.hasPrefix("intrinsic ") && $0.hasSuffix("font 10.0") }, traced.calls.description)
    XCTAssertTrue(traced.calls.contains { $0.hasPrefix("cellSize ") }, traced.calls.description)
  }

  func testTheMeasuredValueComesBackUnchanged() throws {
    let view = TextField("minutes", text: .constant("")).font(.caption)
    let untraced = try AppearanceRender.size(view)

    let traced = try TextFieldSizingTrace.record { try AppearanceRender.size(view) }

    XCTAssertEqual(traced.value, untraced)
  }

  func testEveryHookedMethodIsRestoredOnceTheTraceCloses() throws {
    let before = implementations()

    _ = try TextFieldSizingTrace.record { try AppearanceRender.size(TextField("m", text: .constant(""))) }

    XCTAssertEqual(implementations(), before)
  }

  func testEveryHookedMethodIsRestoredWhenTheMeasurementThrows() {
    let before = implementations()

    XCTAssertThrowsError(try TextFieldSizingTrace.record { throw MeasurementFailed() })

    XCTAssertEqual(implementations(), before)
  }

  /// Restored in behaviour as well as in pointer: a plain AppKit field measures as it did before.
  func testATextFieldMeasuresAsBeforeOnceTheTraceCloses() {
    let before = NSTextField(labelWithString: "25 minutes").intrinsicContentSize

    let traced = TextFieldSizingTrace.record {
      NSTextField(labelWithString: "25 minutes").intrinsicContentSize
    }
    let after = NSTextField(labelWithString: "25 minutes").intrinsicContentSize

    XCTAssertEqual(traced.value, before)
    XCTAssertEqual(after, before)
    XCTAssertTrue(traced.calls.contains { $0.hasPrefix("intrinsic ") }, "the trace never saw the field it measured")
  }

  func testADescriptionNamesEachTraceAndKeepsItsCallsInOrder() {
    let description = TextFieldSizingTrace.describe([
      "body": ["setFont AppKitTextField 13.0", "intrinsic AppKitTextField (-1.0, 16.0) font 13.0"],
      "caption": ["setFont AppKitTextField 10.0"],
    ])

    XCTAssertEqual(
      description,
      "\nbody render: setFont AppKitTextField 13.0; intrinsic AppKitTextField (-1.0, 16.0) font 13.0"
        + "\ncaption render: setFont AppKitTextField 10.0",
    )
  }

  // MARK: Private

  private struct MeasurementFailed: Error { }

  /// The address each hooked method currently runs, keyed by where it was looked up.
  private func implementations() -> [String: UInt] {
    let hooked: [(owner: AnyClass, name: String)] = [
      (NSControl.self, "setFont:"),
      (NSTextField.self, "intrinsicContentSize"),
      (NSTextFieldCell.self, "cellSizeForBounds:"),
      (NSTextField.self, "initWithFrame:"),
    ]
    var addresses = [String: UInt]()
    for entry in hooked {
      let method = class_getInstanceMethod(entry.owner, NSSelectorFromString(entry.name))
      addresses["\(entry.owner) \(entry.name)"] = method.map { UInt(bitPattern: method_getImplementation($0)) } ?? 0
    }
    return addresses
  }

}

import AppKit
import ObjectiveC
import SwiftUI
import ThrowntomClient
import XCTest
@testable import ThrowntomUI

// MARK: - ZZDiagProbeTests

/// TEMPORARY CI DIAGNOSTIC for throwntom-repg, not coverage, and must not merge. It measures the
/// entry row at body and at caption many times over, with AppKit's text-field font and sizing calls
/// traced, and writes the call sequence of any pair that is not the usual 37/34 to stderr.
@MainActor
final class ZZDiagProbeTests: XCTestCase {

  // MARK: Internal

  func testTrace() throws {
    installHooks()
    try stressLoop()
  }

  // MARK: Private

  private static let setFont = NSSelectorFromString("setFont:")
  private static let intrinsic = NSSelectorFromString("intrinsicContentSize")
  private static let cellSize = NSSelectorFromString("cellSizeForBounds:")
  private static let initFrame = NSSelectorFromString("initWithFrame:")

  private nonisolated(unsafe) static var calls = [String]()

  private static func emit(_ line: String) {
    FileHandle.standardError.write(Data("DIAG \(line)\n".utf8))
  }

  private static func hook(_ cls: AnyClass, _ selector: Selector, _ make: (IMP) -> Any) {
    guard let method = class_getInstanceMethod(cls, selector) else {
      emit("nohook \(selector)")
      return
    }
    method_setImplementation(method, imp_implementationWithBlock(make(method_getImplementation(method))))
  }

  private static func pointSize(_ object: AnyObject) -> CGFloat {
    (object as? NSControl)?.font?.pointSize ?? (object as? NSCell)?.font?.pointSize ?? -1
  }

  private func installHooks() {
    typealias SetFont = @convention(c) (AnyObject, Selector, NSFont?) -> Void
    typealias SizeGetter = @convention(c) (AnyObject, Selector) -> NSSize
    typealias CellSize = @convention(c) (AnyObject, Selector, NSRect) -> NSSize
    typealias Init = @convention(c) (AnyObject, Selector, NSRect) -> AnyObject
    Self.hook(NSControl.self, Self.setFont) { old in
      let original = unsafeBitCast(old, to: SetFont.self)
      let block: @convention(block) (AnyObject, NSFont?) -> Void = { object, font in
        Self.calls.append("setFont \(type(of: object)) \(font?.pointSize ?? -1)")
        original(object, Self.setFont, font)
      }
      return block
    }
    Self.hook(NSTextField.self, Self.intrinsic) { old in
      let original = unsafeBitCast(old, to: SizeGetter.self)
      let block: @convention(block) (AnyObject) -> NSSize = { object in
        let size = original(object, Self.intrinsic)
        Self.calls.append("intrinsic \(type(of: object)) \(size) font \(Self.pointSize(object))")
        return size
      }
      return block
    }
    Self.hook(NSTextFieldCell.self, Self.cellSize) { old in
      let original = unsafeBitCast(old, to: CellSize.self)
      let block: @convention(block) (AnyObject, NSRect) -> NSSize = { object, bounds in
        let size = original(object, Self.cellSize, bounds)
        Self.calls.append("cellSize \(size) font \(Self.pointSize(object))")
        return size
      }
      return block
    }
    Self.hook(NSTextField.self, Self.initFrame) { old in
      let original = unsafeBitCast(old, to: Init.self)
      let block: @convention(block) (AnyObject, NSRect) -> AnyObject = { object, frame in
        Self.calls.append("init \(type(of: object))")
        return original(object, Self.initFrame, frame)
      }
      return block
    }
  }

  private func stressLoop() throws {
    let iterations = Int(ProcessInfo.processInfo.environment["DIAG_N"] ?? "") ?? 2000
    var tally = [String: Int]()
    var shown = 0
    for index in 0 ..< iterations {
      let environment = AppEnvironment(transport: try StubTransport(states: []))
      environment.windowModel.isEnteringSnooze = true
      let row = SnoozeEntryRow(client: environment.client, model: environment.windowModel) { }
      if index % 3 == 0 {
        row.submit("45")
      }
      if index % 5 == 0 {
        _ = try AppearanceRender.bitmap(row.field, appearance: .darkAqua, scheme: .dark)
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.001))
      Self.calls = []
      let body = try AppearanceRender.size(row.body).height
      let bodyCalls = Self.calls
      Self.calls = []
      let caption = try AppearanceRender.size(row.body.font(.caption)).height
      tally["\(body)/\(caption)", default: 0] += 1
      if body != 37 || caption != 34, shown < 5 {
        shown += 1
        Self.emit("anomaly at \(index) body \(body) caption \(caption)")
        for call in bodyCalls {
          Self.emit("  B \(call)")
        }
        for call in Self.calls {
          Self.emit("  C \(call)")
        }
      }
    }
    Self.emit("tally \(tally)")
  }

}

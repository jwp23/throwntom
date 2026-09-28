import AppKit
import ObjectiveC

// MARK: - TextFieldSizingTrace

/// Records what AppKit does to a text field while one measurement runs, so that a failed size
/// comparison says which font the field was actually measured at (throwntom-repg).
///
/// This is a scoped, per-call diagnostic, not a pattern to reach for elsewhere. It works by
/// replacing four AppKit method implementations process-wide, so every call opens the hooks
/// immediately before `measure` and restores the originals in a `defer` immediately after —
/// thrown or not — and nothing outside that window runs hooked.
///
/// Why hooks rather than reading the view afterwards: `ImageRenderer` exposes no view tree. The
/// `AppKitTextField` it builds sits under an `AppKitPlatformViewHost` with no superview and no
/// window, so after the render nothing can reach it to read its font.
///
/// Each entry is a class name and a measured figure — never the field's text.
@MainActor
enum TextFieldSizingTrace {

  // MARK: Internal

  /// Runs `measure` with the hooks open and returns its value with the calls it made, in order.
  static func record<Value>(_ measure: () throws -> Value) rethrows -> (value: Value, calls: [String]) {
    let recorder = Recorder()
    let restorers = [
      hookSetFont(recorder),
      hookIntrinsicContentSize(recorder),
      hookCellSize(recorder),
      hookInitWithFrame(recorder),
    ]
    defer {
      for restore in restorers {
        restore()
      }
    }
    let value = try measure()
    return (value, recorder.calls)
  }

  /// Each labelled trace on a line of its own, for an assertion's failure message.
  static func describe(_ traces: KeyValuePairs<String, [String]>) -> String {
    traces.map { "\n\($0.key) render: \($0.value.joined(separator: "; "))" }.joined()
  }

  // MARK: Private

  private typealias SetFont = @convention(c) (AnyObject, Selector, NSFont?) -> Void
  private typealias SizeGetter = @convention(c) (AnyObject, Selector) -> NSSize
  private typealias CellSize = @convention(c) (AnyObject, Selector, NSRect) -> NSSize
  private typealias InitWithFrame = @convention(c) (AnyObject, Selector, NSRect) -> AnyObject?

  /// Where the hooks write. One per `record` call, so nothing is shared between traces.
  private final class Recorder {
    var calls = [String]()
  }

  private static func hookSetFont(_ recorder: Recorder) -> () -> Void {
    let selector = NSSelectorFromString("setFont:")
    return replace(selector, in: NSControl.self, recorder: recorder) { original in
      let setFont = unsafeBitCast(original, to: SetFont.self)
      let hook: @convention(block) (AnyObject, NSFont?) -> Void = { control, font in
        recorder.calls.append("setFont \(type(of: control)) \(font?.pointSize ?? -1)")
        setFont(control, selector, font)
      }
      return hook
    }
  }

  private static func hookIntrinsicContentSize(_ recorder: Recorder) -> () -> Void {
    let selector = NSSelectorFromString("intrinsicContentSize")
    return replace(selector, in: NSTextField.self, recorder: recorder) { original in
      let intrinsicContentSize = unsafeBitCast(original, to: SizeGetter.self)
      let hook: @convention(block) (AnyObject) -> NSSize = { field in
        let size = intrinsicContentSize(field, selector)
        recorder.calls.append("intrinsic \(type(of: field)) \(size) font \(pointSize(of: field))")
        return size
      }
      return hook
    }
  }

  private static func hookCellSize(_ recorder: Recorder) -> () -> Void {
    let selector = NSSelectorFromString("cellSizeForBounds:")
    return replace(selector, in: NSTextFieldCell.self, recorder: recorder) { original in
      let cellSize = unsafeBitCast(original, to: CellSize.self)
      let hook: @convention(block) (AnyObject, NSRect) -> NSSize = { cell, bounds in
        let size = cellSize(cell, selector, bounds)
        recorder.calls.append("cellSize \(size) font \(pointSize(of: cell))")
        return size
      }
      return hook
    }
  }

  private static func hookInitWithFrame(_ recorder: Recorder) -> () -> Void {
    let selector = NSSelectorFromString("initWithFrame:")
    return replace(selector, in: NSTextField.self, recorder: recorder) { original in
      let initWithFrame = unsafeBitCast(original, to: InitWithFrame.self)
      let hook: @convention(block) (AnyObject, NSRect) -> AnyObject? = { view, frame in
        if view is NSTextField {
          recorder.calls.append("init \(type(of: view))")
        }
        return initWithFrame(view, selector, frame)
      }
      return hook
    }
  }

  /// Swaps in the block `makeHook` builds around the current implementation, and returns what puts
  /// that implementation back. A method that cannot be found is recorded rather than hooked.
  private static func replace(
    _ selector: Selector,
    in cls: AnyClass,
    recorder: Recorder,
    makeHook: (IMP) -> Any,
  ) -> () -> Void {
    guard let method = class_getInstanceMethod(cls, selector) else {
      recorder.calls.append("unhooked \(cls) \(selector)")
      return { }
    }
    let original = method_getImplementation(method)
    let hook = imp_implementationWithBlock(makeHook(original))
    method_setImplementation(method, hook)
    return {
      method_setImplementation(method, original)
      imp_removeBlock(hook)
    }
  }

  private static func pointSize(of object: AnyObject) -> CGFloat {
    (object as? NSControl)?.font?.pointSize ?? (object as? NSCell)?.font?.pointSize ?? -1
  }

}

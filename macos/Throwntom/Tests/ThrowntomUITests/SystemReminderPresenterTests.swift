import AppKit
import XCTest
@testable import ThrowntomUI

/// The real, unstubbed pass-through to AppKit. Most of `SystemReminderPresenter` reaches for
/// `UNUserNotificationCenter`, which no test process may reach (see the type's own doc comment),
/// so only the AppKit-only surface — the Dock bounce and the window ordering — is exercised here.
@MainActor
final class SystemReminderPresenterTests: XCTestCase {

  // MARK: Internal

  /// `requestAttention()`'s idempotency guard has no field this test can read directly, so it is
  /// read the way anything outside the presenter can: through `NSApp`'s own attention-request
  /// counter. A request-then-cancel probe is a no-op on that counter unless something else's
  /// request is left outstanding in between, so the counter having moved between two probes is
  /// itself the signal that the presenter issued a real request in that gap.
  func testASecondCallWhileARequestIsOutstandingIssuesNothingNew() {
    _ = NSApplication.shared
    let presenter = SystemReminderPresenter()

    let baseline = probeAttentionCounter()
    presenter.requestAttention()
    let afterFirstCall = probeAttentionCounter()
    presenter.requestAttention()
    let afterSecondCall = probeAttentionCounter()
    presenter.cancelAttention()

    XCTAssertEqual(afterFirstCall, baseline + 1, "the first call must ask NSApp for the user's attention")
    XCTAssertEqual(afterSecondCall, afterFirstCall, "a second call must not ask again while one is outstanding")
  }

  /// The one window eligible to be raised — not a sheet, and able to become key even though this
  /// never asks it to — is the one that ends up on screen.
  func testTheEligibleWindowIsOrderedFrontWithoutBecomingKey() {
    _ = NSApplication.shared
    let window = makeWindow(styleMask: [.titled, .closable])
    XCTAssertFalse(window.isVisible)

    SystemReminderPresenter().showWindowWithoutFocus()

    XCTAssertTrue(window.isVisible, "the eligible window must be raised")
    XCTAssertFalse(window.isKeyWindow, "raising it must never hand it the keyboard")
  }

  /// A window that cannot become key is not a candidate at all: `&&` excludes it however its
  /// `isSheet` reads, so nothing raises it. Mutating `&&` to `||` would let `!isSheet` alone
  /// qualify a plain, non-key-able window - this window has no other qualifying window beside it,
  /// so a wrong `||` is the only way it could ever be raised.
  func testAWindowThatCannotBecomeKeyIsNeverRaised() {
    _ = NSApplication.shared
    let window = makeWindow(styleMask: [.borderless])
    XCTAssertFalse(window.canBecomeKey)
    XCTAssertFalse(window.isSheet)

    SystemReminderPresenter().showWindowWithoutFocus()

    XCTAssertFalse(window.isVisible, "a window that cannot become key must never be raised")
  }

  // MARK: Private

  private func makeWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
    NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: styleMask,
      backing: .buffered,
      defer: true,
    )
  }

  /// Asks `NSApp` for the user's attention and immediately cancels it. This is a no-op on the
  /// counter `NSApp` hands back unless some other request was left outstanding in between two
  /// probes, which is what makes the counter usable as a read on the presenter's own private state.
  private func probeAttentionCounter() -> Int {
    let id = NSApp.requestUserAttention(.criticalRequest)
    NSApp.cancelUserAttentionRequest(id)
    return id
  }

}

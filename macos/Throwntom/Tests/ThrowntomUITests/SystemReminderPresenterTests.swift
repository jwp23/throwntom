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

  /// `cancelAttention()` leaves `attentionRequest` nil whether or not it tells `NSApp` to stop
  /// bouncing the Dock, so the field is not the signal: the counter is, again. A request that was
  /// really cancelled lets the counter fall back to its unclaimed baseline; one that was not stays
  /// outstanding, so every later probe has to claim a new number instead of reusing that baseline.
  func testCancellingAttentionReleasesTheOutstandingRequest() {
    _ = NSApplication.shared
    let baseline = probeAttentionCounter()

    let presenter = SystemReminderPresenter()
    presenter.requestAttention()
    presenter.cancelAttention()

    XCTAssertEqual(probeAttentionCounter(), baseline, "cancelling must hand the request back to NSApp")
    XCTAssertEqual(probeAttentionCounter(), baseline, "the request must not still be outstanding afterwards")
  }

  /// The one window eligible to be raised — not a sheet, and able to become key even though this
  /// never asks it to — is the one that ends up on screen.
  ///
  /// `showWindowWithoutFocus()` picks `NSApp.windows.first`, which is *every* window any test in
  /// this process has created and not yet deallocated — not just this test's own window, and
  /// `NSApp.windows` guarantees no ordering among them (the source's own comment). Closing a
  /// window that was never raised crashes the whole process asynchronously (confirmed by hand:
  /// `NSWindow.close()` on one that never had `orderFrontRegardless`/`makeKeyAndOrderFront` called
  /// on it segfaults on this toolchain, deferred or not — this is why no test file in this target,
  /// including this one, ever calls `close()` on a window it merely constructed). This test's own
  /// window really is raised, by the code under test, and closing a raised window is itself safe —
  /// but AppKit only reflects that close back into `NSApp.windows` after the run loop turns, and
  /// spinning the run loop even once here was measured to crash elsewhere in the full suite (stray
  /// half-torn-down windows other tests in this target already leave behind, never before exposed
  /// because nothing in this synchronous suite ever pumped a run loop). So this window is left
  /// alive on purpose, the same as every other window test's, and registered below so
  /// `assertNoOtherEligibleWindow()` knows it is accounted for rather than stray.
  func testTheEligibleWindowIsOrderedFrontWithoutBecomingKey() {
    _ = NSApplication.shared
    assertNoOtherEligibleWindow()
    let window = makeWindow(styleMask: [.titled, .closable])
    XCTAssertFalse(window.isVisible)

    SystemReminderPresenter().showWindowWithoutFocus()

    XCTAssertTrue(
      window === NSApp.windows.first { $0.canBecomeKey && !$0.isSheet },
      "this window must be the one presenter picked",
    )
    XCTAssertTrue(window.isVisible, "the eligible window must be raised")
    XCTAssertFalse(window.isKeyWindow, "raising it must never hand it the keyboard")

    Self.acknowledgedWindows.insert(ObjectIdentifier(window))
  }

  /// A window that cannot become key is not a candidate at all: `&&` excludes it however its
  /// `isSheet` reads, so nothing raises it. Mutating `&&` to `||` would let `!isSheet` alone
  /// qualify a plain, non-key-able window. `assertNoOtherEligibleWindow()` guarantees this window
  /// has no other qualifying window beside it to absorb the mutant's match instead of exposing it
  /// on this one, which is what would let the mutant hide behind a stray window and false-pass.
  func testAWindowThatCannotBecomeKeyIsNeverRaised() {
    _ = NSApplication.shared
    assertNoOtherEligibleWindow()
    let window = makeWindow(styleMask: [.borderless])
    XCTAssertFalse(window.canBecomeKey)
    XCTAssertFalse(window.isSheet)

    SystemReminderPresenter().showWindowWithoutFocus()

    XCTAssertFalse(window.isVisible, "a window that cannot become key must never be raised")
  }

  // MARK: Private

  /// Windows this file has deliberately raised and left alive rather than fought AppKit to remove
  /// — see `testTheEligibleWindowIsOrderedFrontWithoutBecomingKey`'s doc comment for why. Tracked
  /// by identity, not by strong reference: this exists so `assertNoOtherEligibleWindow()` can tell
  /// "a window this file already accounted for" from "a window some test forgot," not to keep any
  /// of them alive — AppKit is already doing that.
  private static var acknowledgedWindows = Set<ObjectIdentifier>()

  private func makeWindow(styleMask: NSWindow.StyleMask) -> NSWindow {
    NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: styleMask,
      backing: .buffered,
      defer: true,
    )
  }

  /// Fails loudly, naming the offending window, if a titled non-sheet window neither this file
  /// acknowledged nor merely constructed-and-dropped by ARC is still alive in this process. A
  /// window that is only ever constructed, never shown, is a method-local `let` that ARC
  /// deallocates — dropping it from `NSApp.windows` — before the next test method starts. A window
  /// that has actually been ordered front is different: AppKit keeps its own retain on a shown
  /// window, so ARC scope exit alone does not deallocate it, and it stays in `NSApp.windows` for
  /// the rest of the process — `acknowledgedWindows` is what lets this check see past the one this
  /// file already knows about instead of misreporting it as some future test's stray window.
  private func assertNoOtherEligibleWindow(file: StaticString = #filePath, line: UInt = #line) {
    let stray = NSApp.windows
      .filter { $0.canBecomeKey && !$0.isSheet && !Self.acknowledgedWindows.contains(ObjectIdentifier($0)) }
    XCTAssertTrue(
      stray.isEmpty,
      "an eligible window from another test is still alive and would race this one: \(stray)",
      file: file,
      line: line,
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

import AppKit
import XCTest
@testable import ThrowntomUI

// MARK: - StubLoginItemRegistrar

/// Reports what macOS would, and can refuse a change the way SMAppService does when the
/// login item is managed or its approval was revoked.
private struct StubLoginItemRegistrar: LoginItemRegistrar {
  var loginItemEnabled = false
  var refusal: Error?
  /// Which requested values the refusal applies to; defaults to both. Real SMAppService can
  /// refuse `register()` while still letting `unregister()` no-op on an already-unregistered item.
  var refuses: (Bool) -> Bool = { _ in true }

  func setLoginItem(_ enabled: Bool) throws {
    if let refusal, refuses(enabled) {
      throw refusal
    }
  }
}

// MARK: - LoginItemRefused

private struct LoginItemRefused: LocalizedError {
  var errorDescription: String? {
    "Operation not permitted"
  }
}

// MARK: - LoginItemSettingTests

final class LoginItemSettingTests: XCTestCase {
  func testEnablingLeavesTheToggleOnWithNothingToReport() {
    let setting = LoginItemSetting.afterSetting(
      true,
      in: StubLoginItemRegistrar(),
      current: LoginItemSetting(isOn: false, message: nil),
    )

    XCTAssertEqual(setting, LoginItemSetting(isOn: true, message: nil))
  }

  func testDisablingLeavesTheToggleOffWithNothingToReport() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: true)

    let setting = LoginItemSetting.afterSetting(
      false,
      in: registrar,
      current: LoginItemSetting(isOn: true, message: nil),
    )

    XCTAssertEqual(setting, LoginItemSetting(isOn: false, message: nil))
  }

  func testARefusalIsReportedAndLeavesTheToggleWhereMacOSSaysItIs() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: true, refusal: LoginItemRefused())

    let setting = LoginItemSetting.afterSetting(
      false,
      in: registrar,
      current: LoginItemSetting(isOn: true, message: nil),
    )

    XCTAssertEqual(setting, LoginItemSetting(isOn: true, message: "Login item: macOS refused the change."))
  }

  /// `SMAppService` refuses through plain `NSError`s as often as through described ones, and an
  /// undescribed `NSError` reads as its domain and code. The menu says the same thing either way:
  /// the reader is being told the switch did not move, and a framework's error identity is not
  /// part of that.
  func testMacOSsOwnErrorTextNeverReachesTheMenu() throws {
    let undescribed = NSError(domain: "SMAppServiceErrorDomain", code: 1)
    let registrar = StubLoginItemRegistrar(loginItemEnabled: true, refusal: undescribed)

    let setting = LoginItemSetting.afterSetting(
      false,
      in: registrar,
      current: LoginItemSetting(isOn: true, message: nil),
    )

    let message = try XCTUnwrap(setting.message)
    XCTAssertFalse(message.contains("SMAppServiceErrorDomain"), message)
    XCTAssertFalse(message.lowercased().contains("error 1"), message)
    XCTAssertEqual(message, "Login item: macOS refused the change.")
  }

  func testARefusalToEnableLeavesTheToggleOff() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: false, refusal: LoginItemRefused())

    let setting = LoginItemSetting.afterSetting(
      true,
      in: registrar,
      current: LoginItemSetting(isOn: false, message: nil),
    )

    XCTAssertFalse(setting.isOn)
    XCTAssertNotNil(setting.message)
  }

  func testABouncedToggleDoesNotWipeTheFailureMessage() {
    // Managed/revoked item: registering is refused, but unregistering an already-unregistered
    // item is not — the way SMAppService behaves.
    let registrar = StubLoginItemRegistrar(loginItemEnabled: false, refusal: LoginItemRefused(), refuses: { $0 })

    let afterFailure = LoginItemSetting.afterSetting(
      true,
      in: registrar,
      current: LoginItemSetting(isOn: false, message: nil),
    )
    XCTAssertEqual(afterFailure, LoginItemSetting(isOn: false, message: "Login item: macOS refused the change."))

    // The toggle's isOn snapped back to false, which changes it again and re-fires onChange with
    // the opposite value, exactly what LoginItemToggle receives next.
    let afterBounce = LoginItemSetting.afterSetting(afterFailure.isOn, in: registrar, current: afterFailure)

    XCTAssertEqual(afterBounce, afterFailure, "the bounce must not erase the failure message")
  }
}

// MARK: - RecordingLoginItemRegistrar

/// Counts what `LoginItemToggle`'s own wiring asks for and does, rather than what `afterSetting`
/// decides for it — `LoginItemSettingTests` above covers the decision; `LoginItemToggleWiringTests`
/// below covers whether the view actually calls into it.
private final class RecordingLoginItemRegistrar: LoginItemRegistrar {

  // MARK: Lifecycle

  /// `thenEnabled` is what macOS answers from the second read on. Its answer is live: approval
  /// revoked while the menu is open leaves the state the toggle read when it appeared stale by the
  /// time it acts on that state. Defaults to the same answer throughout.
  init(loginItemEnabled: Bool, thenEnabled: Bool? = nil, refusal: Error? = nil) {
    enabledValue = loginItemEnabled
    laterValue = thenEnabled ?? loginItemEnabled
    self.refusal = refusal
  }

  // MARK: Internal

  private(set) var enabledReads = 0
  private(set) var setValues = [Bool]()
  var refusal: Error?

  var loginItemEnabled: Bool {
    enabledReads += 1
    return enabledReads == 1 ? enabledValue : laterValue
  }

  func setLoginItem(_ enabled: Bool) throws {
    setValues.append(enabled)
    if let refusal {
      throw refusal
    }
  }

  // MARK: Private

  private let enabledValue: Bool
  private let laterValue: Bool

}

// MARK: - LoginItemToggleWiringTests

/// What `LoginItemToggle.body` is actually made of and does: the toggle wired to `onChange` and
/// `onAppear`, and the state it starts in before either has run. These fire the wiring on a value
/// SwiftUI was never handed, where `@State` has no backing store, so they read the wiring's own
/// effects on the registrar rather than reading `setting` back out of a second `body` evaluation.
/// `LoginItemToggleRenderingTests` below takes the other route, hosting the view so SwiftUI runs
/// the wiring itself against installed state.
@MainActor
final class LoginItemToggleWiringTests: XCTestCase {

  // MARK: Internal

  func testTheToggleAsksTheRegistrarForTheCurrentStateWhenItAppears() throws {
    let registrar = RecordingLoginItemRegistrar(loginItemEnabled: true)
    let toggle = LoginItemToggle(registrar: registrar)
    let onAppear = try XCTUnwrap(try onAppearAction(of: toggle), "the toggle has no onAppear wiring")

    onAppear()

    XCTAssertEqual(registrar.enabledReads, 1, "onAppear must read the registrar's own answer, not assume one")
  }

  func testChangingTheToggleAsksTheRegistrarToApplyTheNewValue() throws {
    let registrar = RecordingLoginItemRegistrar(loginItemEnabled: true)
    let toggle = LoginItemToggle(registrar: registrar)
    let onChange = try XCTUnwrap(try onChangeAction(of: toggle), "the toggle has no onChange wiring")

    onChange(true, false)

    XCTAssertEqual(registrar.setValues, [false], "the toggle's own onChange must hand the new value to the registrar")
  }

  /// LoginItemToggle.swift:22:55. The toggle starts off until `onAppear` corrects it from the
  /// registrar; the initial literal is only ever observable before that runs, which is exactly
  /// what `@State`'s own lazy-default thunk still is at this point.
  func testTheDefaultSettingStartsWithTheToggleOff() throws {
    let toggle = LoginItemToggle(registrar: RecordingLoginItemRegistrar(loginItemEnabled: false))

    XCTAssertEqual(try defaultSetting(of: toggle), LoginItemSetting(isOn: false, message: nil))
  }

  // MARK: Private

  private func toggleLayers(of toggle: LoginItemToggle) throws -> [Any] {
    modifierLayers(of: try part(0, of: try tupleParts(of: toggle.body)))
  }

  private func onChangeAction(of toggle: LoginItemToggle) throws -> ((Bool, Bool) -> Void)? {
    try child("action", of: try part(0, of: try toggleLayers(of: toggle))) as? (Bool, Bool) -> Void
  }

  private func onAppearAction(of toggle: LoginItemToggle) throws -> (() -> Void)? {
    try child("appear", of: try part(2, of: try toggleLayers(of: toggle))) as? () -> Void
  }

  /// `@State`'s own uninstalled backing storage: a lazy thunk that produces the property's default
  /// value, read the same way regardless of whether anything has run yet — reached by name because
  /// there is no public API for it.
  private func defaultSetting(of toggle: LoginItemToggle) throws -> LoginItemSetting {
    let lazyState = try child("__setting", of: toggle)
    let storage = try child("_storage", of: lazyState)
    let thunk = try XCTUnwrap(try child("thunk", of: storage) as? () -> LoginItemSetting)
    return thunk()
  }

}

// MARK: - LoginItemToggleRenderingTests

/// Whether the refusal reaches the screen. Hosted in a real window, so SwiftUI installs the
/// toggle's `@State`, runs the view's own `onAppear` and the `onChange` that follows from it, and
/// lays out whatever they leave behind — which is the only place the message is observable.
@MainActor
final class LoginItemToggleRenderingTests: XCTestCase {

  // MARK: Internal

  /// The refused message is a whole extra line under the switch, so a toggle carrying one fits
  /// taller than one that does not. Both registrars report the login item on when the toggle
  /// appears and off by the time it writes that back, so both are asked for the same change and
  /// the refusal is the only difference between the two windows.
  func testARefusedChangePutsItsMessageUnderTheSwitch() {
    let refusing = RecordingLoginItemRegistrar(loginItemEnabled: true, thenEnabled: false, refusal: LoginItemRefused())
    let accepting = RecordingLoginItemRegistrar(loginItemEnabled: true, thenEnabled: false)

    let refused = hostInWindow(LoginItemToggle(registrar: refusing))
    let accepted = hostInWindow(LoginItemToggle(registrar: accepting))
    waitForTheExtraLine(in: refused.view, against: accepted.view)

    XCTAssertEqual(refusing.setValues, [true], "the refused toggle never asked macOS for the change")
    XCTAssertEqual(accepting.setValues, [true], "the accepted toggle never asked macOS for the change")
    XCTAssertGreaterThan(
      refused.view.fittingSize.height,
      accepted.view.fittingSize.height,
      "the refusal is not on screen: the refused toggle fits in the same height as the accepted one",
    )
  }

  // MARK: Private

  /// `onAppear` runs a runloop turn after the window lays the view out and the `onChange` it sets
  /// off lands a turn after that, so the size is asked for repeatedly rather than once. Only a
  /// genuine failure pays the full deadline.
  private func waitForTheExtraLine(in refused: NSView, against accepted: NSView) {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline, refused.fittingSize.height <= accepted.fittingSize.height {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
  }

}

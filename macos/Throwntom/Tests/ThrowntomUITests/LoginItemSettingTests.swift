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

  init(loginItemEnabled: Bool, refusal: Error? = nil) {
    enabledValue = loginItemEnabled
    self.refusal = refusal
  }

  // MARK: Internal

  private(set) var enabledReads = 0
  private(set) var setValues = [Bool]()
  var refusal: Error?

  var loginItemEnabled: Bool {
    enabledReads += 1
    return enabledValue
  }

  func setLoginItem(_ enabled: Bool) throws {
    setValues.append(enabled)
    if let refusal {
      throw refusal
    }
  }

  // MARK: Private

  private let enabledValue: Bool

}

// MARK: - LoginItemToggleWiringTests

/// What `LoginItemToggle.body` is actually made of and does: the toggle wired to `onChange` and
/// `onAppear`, and the state it starts in before either has run. `SwiftUI` never installs a real
/// `@State` location in this process (confirmed by hand: hosting the view in a real `NSWindow` and
/// firing its `onChange` still leaves `_location` nil), so this reads the wiring's own effects on
/// the registrar rather than reading `setting` back out of a second `body` evaluation.
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

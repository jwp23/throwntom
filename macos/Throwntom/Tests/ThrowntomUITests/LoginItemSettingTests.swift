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

    XCTAssertEqual(setting, LoginItemSetting(isOn: true, message: "Login item: Operation not permitted"))
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
    XCTAssertEqual(afterFailure, LoginItemSetting(isOn: false, message: "Login item: Operation not permitted"))

    // The toggle's isOn snapped back to false, which changes it again and re-fires onChange with
    // the opposite value, exactly what PopoverView.setLoginItem receives next.
    let afterBounce = LoginItemSetting.afterSetting(afterFailure.isOn, in: registrar, current: afterFailure)

    XCTAssertEqual(afterBounce, afterFailure, "the bounce must not erase the failure message")
  }
}

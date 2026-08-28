import XCTest
@testable import ThrowntomUI

// MARK: - StubLoginItemRegistrar

/// Reports what macOS would, and can refuse a change the way SMAppService does when the
/// login item is managed or its approval was revoked.
private struct StubLoginItemRegistrar: LoginItemRegistrar {
  var loginItemEnabled = false
  var refusal: Error?

  func setLoginItem(_: Bool) throws {
    if let refusal {
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
    let setting = LoginItemSetting.afterSetting(true, in: StubLoginItemRegistrar())

    XCTAssertEqual(setting, LoginItemSetting(isOn: true, message: nil))
  }

  func testDisablingLeavesTheToggleOffWithNothingToReport() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: true)

    let setting = LoginItemSetting.afterSetting(false, in: registrar)

    XCTAssertEqual(setting, LoginItemSetting(isOn: false, message: nil))
  }

  func testARefusalIsReportedAndLeavesTheToggleWhereMacOSSaysItIs() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: true, refusal: LoginItemRefused())

    let setting = LoginItemSetting.afterSetting(false, in: registrar)

    XCTAssertEqual(setting, LoginItemSetting(isOn: true, message: "Login item: Operation not permitted"))
  }

  func testARefusalToEnableLeavesTheToggleOff() {
    let registrar = StubLoginItemRegistrar(loginItemEnabled: false, refusal: LoginItemRefused())

    let setting = LoginItemSetting.afterSetting(true, in: registrar)

    XCTAssertFalse(setting.isOn)
    XCTAssertNotNil(setting.message)
  }
}

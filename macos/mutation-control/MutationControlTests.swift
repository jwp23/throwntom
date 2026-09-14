import XCTest
@testable import ThrowntomClient

/// Deliberately omits the zero boundary; see MutationControl.swift.
final class MutationControlTests: XCTestCase {
  func testPositiveAndNegativeValues() {
    XCTAssertTrue(MutationControl.isPositive(5))
    XCTAssertFalse(MutationControl.isPositive(-5))
  }
}

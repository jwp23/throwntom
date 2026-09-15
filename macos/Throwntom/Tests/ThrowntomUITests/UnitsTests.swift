import SwiftUI
import XCTest
@testable import ThrowntomUI

final class UnitsTests: XCTestCase {
  func testPointScalesDesignUnitsIntoTheRect() {
    let units = Units(rect: CGRect(x: 10, y: 20, width: 200, height: 200))
    XCTAssertEqual(units.scale, 2)
    XCTAssertEqual(units.point(50, 56), CGPoint(x: 110, y: 132))
    XCTAssertEqual(units.length(34), 68)
  }

  func testDesignShapeDrawsInTheGivenRect() {
    let shape = DesignShape { path, units in path.circle(units, 50, 50, 10) }
    let bounds = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 100)).boundingRect
    XCTAssertEqual(bounds, CGRect(x: 40, y: 40, width: 20, height: 20))
  }

  func testPolygonClosesAndCurvesReachTheirEnd() {
    let units = Units(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var polygon = Path()
    polygon.polygon(units, [(0, 0), (10, 0), (10, 10)])
    XCTAssertEqual(polygon.boundingRect, CGRect(x: 0, y: 0, width: 10, height: 10))
    var curve = Path()
    curve.move(units, 0, 0)
    curve.curve(units, 0, 10, 10, 10, 10, 0)
    XCTAssertEqual(curve.currentPoint, CGPoint(x: 10, y: 0))
  }

  func testRotatedEllipseIsCentredWhereAsked() {
    let units = Units(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var path = Path()
    path.ellipse(units, 27, 42, 8, 5, rotation: -25)
    XCTAssertEqual(path.boundingRect.midX, 27, accuracy: 0.01)
    XCTAssertEqual(path.boundingRect.midY, 42, accuracy: 0.01)
  }

  /// The centre point is rotation-invariant (the ellipse is drawn about the origin, then moved),
  /// so only its axes prove the degrees-to-radians conversion: at 90 degrees the long and short
  /// axes swap.
  func testRotatedEllipseSwapsItsAxesAtNinetyDegrees() {
    let units = Units(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var path = Path()
    path.ellipse(units, 50, 50, 10, 5, rotation: 90)
    XCTAssertEqual(path.boundingRect.width, 10, accuracy: 0.01)
    XCTAssertEqual(path.boundingRect.height, 20, accuracy: 0.01)
  }

  func testRoundedRectSizesFromTwiceItsHalfWidthAndHalfHeight() {
    let units = Units(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var path = Path()
    path.roundedRect(units, 50, 50, 20, 10, radius: 5)
    XCTAssertEqual(path.boundingRect.width, 40, accuracy: 0.01)
    XCTAssertEqual(path.boundingRect.height, 20, accuracy: 0.01)
  }

  func testPolygonClosesBackToItsStartingPoint() {
    let units = Units(rect: CGRect(x: 0, y: 0, width: 100, height: 100))
    var path = Path()
    path.polygon(units, [(0, 0), (10, 0), (10, 10)])
    XCTAssertEqual(path.currentPoint, CGPoint(x: 0, y: 0))
  }
}

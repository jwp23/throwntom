import XCTest
@testable import ThrowntomClient

final class HTTPParserTests: XCTestCase {
  func testParsesHeadAndReportsBodyStart() throws {
    let raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
    let parsed = try XCTUnwrap(try HTTPParser.parseHead(Data(raw.utf8)))
    XCTAssertEqual(parsed.head.status, 200)
    XCTAssertEqual(parsed.head.headers["content-type"], "application/json")
    XCTAssertEqual(parsed.head.headers["content-length"], "2")
    XCTAssertEqual(parsed.bodyStart, raw.utf8.count - 2)
  }

  func testIncompleteHeadReturnsNil() throws {
    XCTAssertNil(try HTTPParser.parseHead(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n".utf8)))
  }

  func testRejectsMalformedStatusLine() {
    XCTAssertThrowsError(try HTTPParser.parseHead(Data("BOGUS\r\n\r\n".utf8))) { error in
      XCTAssertEqual(error as? HTTPParseError, .malformedStatusLine("BOGUS"))
    }
  }

  func testRejectsOversizedHead() {
    let huge = Data("HTTP/1.1 200 OK\r\nX: ".utf8) + Data(repeating: UInt8(ascii: "a"), count: HTTPParser.maxHeadBytes)
    XCTAssertThrowsError(try HTTPParser.parseHead(huge)) { error in
      XCTAssertEqual(error as? HTTPParseError, .headTooLarge)
    }
  }

  func testParsesHeadFromNonZeroOffsetSlice() throws {
    let raw = Data("XXXX".utf8) + Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}".utf8)
    let slice = raw[4...]
    let parsed = try XCTUnwrap(try HTTPParser.parseHead(slice))
    XCTAssertEqual(parsed.head.status, 200)
    // The head ends with "\r\n\r\n", which is 38 bytes into the HTTP response portion.
    // bodyStart is the offset from the slice's start, so it's 38.
    XCTAssertEqual(parsed.bodyStart, 38)
  }
}

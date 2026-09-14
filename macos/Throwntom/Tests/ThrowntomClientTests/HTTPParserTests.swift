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

  func testHeadAtExactlyMaxSizeWithoutTerminatorReturnsNil() throws {
    // 13:21 RelationalOperatorReplacement (> -> >=): data.count == maxHeadBytes must NOT throw
    // when the terminator hasn't arrived yet -- only a size strictly greater than the limit does.
    let data = Data(repeating: UInt8(ascii: "a"), count: HTTPParser.maxHeadBytes)
    XCTAssertNil(try HTTPParser.parseHead(data))
  }

  func testHeadSizeCheckUsesTheSlicesOwnOffsetNotTheParentBuffers() throws {
    // 18:25 ArithmeticOperatorReplacement (- -> +): the head-size check must be relative to the
    // slice's own startIndex, not the parent buffer's absolute offset. A slice taken far into a
    // larger buffer keeps the parent's indices, so a `+` here would overcount using the parent
    // offset even though the actual head is tiny.
    let prefix = Data(repeating: UInt8(ascii: "a"), count: 40_000)
    let head = "HTTP/1.1 200 OK\r\nX: y\r\n"
    let raw = prefix + Data(head.utf8) + Data("\r\n\r\n".utf8) + Data("{}".utf8)
    let slice = raw[prefix.count...]
    let parsed = try XCTUnwrap(try HTTPParser.parseHead(slice))
    XCTAssertEqual(parsed.head.status, 200)
  }

  func testHeadAtExactlyMaxSizeIsAccepted() throws {
    // 18:43 RelationalOperatorReplacement (> -> >=): a head exactly maxHeadBytes long (measured
    // up to but excluding the terminator) must parse, not throw -- only strictly larger heads do.
    let padding = String(repeating: "a", count: 65_516)
    let raw = "HTTP/1.1 200 OK\r\nX: \(padding)\r\n\r\n{}"
    let parsed = try XCTUnwrap(try HTTPParser.parseHead(Data(raw.utf8)))
    XCTAssertEqual(parsed.head.status, 200)
  }

  func testStatusLineWithoutReasonPhraseParses() throws {
    // 25:23 RelationalOperatorReplacement (>= -> >): a status line with no reason phrase splits
    // into exactly 2 parts, which must still be accepted.
    let parsed = try XCTUnwrap(try HTTPParser.parseHead(Data("HTTP/1.1 200\r\n\r\n".utf8)))
    XCTAssertEqual(parsed.head.status, 200)
  }
}

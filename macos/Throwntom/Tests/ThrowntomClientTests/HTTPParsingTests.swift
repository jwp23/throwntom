import XCTest
@testable import ThrowntomClient

final class HTTPParsingTests: XCTestCase {
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

  func testChunkedDecoderAcrossSplitBoundaries() throws {
    var decoder = ChunkedDecoder()
    let stream = "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
    var out = Data()
    // Feed one byte at a time to prove the decoder keeps state across boundaries.
    for byte in stream.utf8 {
      out += try decoder.feed(Data([byte]))
    }
    XCTAssertEqual(String(decoding: out, as: UTF8.self), "hello world")
    XCTAssertTrue(decoder.isFinished)
  }

  func testChunkedDecoderToleratesExtensionAndUppercaseHex() throws {
    var decoder = ChunkedDecoder()
    let out = try decoder.feed(Data("A;name=v\r\n0123456789\r\n0\r\n\r\n".utf8))
    XCTAssertEqual(String(decoding: out, as: UTF8.self), "0123456789")
    XCTAssertTrue(decoder.isFinished)
  }

  func testChunkedDecoderRejectsBadSize() {
    var decoder = ChunkedDecoder()
    XCTAssertThrowsError(try decoder.feed(Data("zz\r\nab\r\n".utf8))) { error in
      XCTAssertEqual(error as? HTTPParseError, .malformedChunkSize("zz"))
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

  func testChunkedDecoderRejectsNegativeSize() {
    var decoder = ChunkedDecoder()
    XCTAssertThrowsError(try decoder.feed(Data("-1\r\nab\r\n".utf8))) { error in
      XCTAssertEqual(error as? HTTPParseError, .malformedChunkSize("-1"))
    }
  }

  func testChunkedDecoderRejectsOversizedChunk() {
    var decoder = ChunkedDecoder()
    XCTAssertThrowsError(try decoder.feed(Data("FFFFFFFF\r\n".utf8))) { error in
      XCTAssertEqual(error as? HTTPParseError, .malformedChunkSize("FFFFFFFF"))
    }
  }
}

import XCTest
@testable import ThrowntomClient

final class ChunkedDecoderTests: XCTestCase {
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

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
    // Bounded: the body and its trailing terminator arrive in one call, which is the
    // shape that stalls the decoder if it fails to move past the body phase exactly
    // when the last body byte matches the announced remaining count.
    let expectation = XCTestExpectation(description: "feed decodes an extension-tagged, uppercase-hex chunk")
    var result = Result<Data, Error>.success(Data())
    var isFinished = false
    DispatchQueue.global().async {
      var decoder = ChunkedDecoder()
      result = Result { try decoder.feed(Data("A;name=v\r\n0123456789\r\n0\r\n\r\n".utf8)) }
      isFinished = decoder.isFinished
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
    let out = try result.get()
    XCTAssertEqual(String(decoding: out, as: UTF8.self), "0123456789")
    XCTAssertTrue(isFinished)
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

  func testChunkedDecoderStartsNotFinished() {
    let decoder = ChunkedDecoder()
    XCTAssertFalse(decoder.isFinished)
  }

  func testChunkedDecoderAllowsSizeLineAtByteLimit() {
    var decoder = ChunkedDecoder()
    let sizeLinePrefix = String(repeating: "a", count: 64)
    XCTAssertNoThrow(try decoder.feed(Data(sizeLinePrefix.utf8)))
  }

  func testChunkedDecoderAllowsChunkAtSizeLimit() {
    var decoder = ChunkedDecoder()
    XCTAssertNoThrow(try decoder.feed(Data("100000\r\n".utf8)))
  }

  func testFeedReturnsWhenBodyBufferIsEmpty() {
    let expectation = XCTestExpectation(description: "feed returns without more body data")
    DispatchQueue.global().async {
      var decoder = ChunkedDecoder()
      _ = try? decoder.feed(Data("5\r\n".utf8))
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
  }

  func testChunkedDecoderRejectsBadTerminatorAsSoonAsTwoBytesArrive() {
    // Bounded: the body and the (malformed) terminator arrive in one call, the same
    // exact-body-match shape that can stall the decoder before it ever inspects
    // the terminator bytes.
    let expectation = XCTestExpectation(description: "feed rejects a malformed terminator without hanging")
    var thrown: Error?
    DispatchQueue.global().async {
      var decoder = ChunkedDecoder()
      do {
        _ = try decoder.feed(Data("3\r\nfooXY".utf8))
      } catch {
        thrown = error
      }
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)
    XCTAssertEqual(thrown as? HTTPParseError, .malformedChunkTerminator)
  }
}

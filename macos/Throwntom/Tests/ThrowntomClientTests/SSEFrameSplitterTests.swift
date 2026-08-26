import XCTest
@testable import ThrowntomClient

final class SSEFrameSplitterTests: XCTestCase {
    func testYieldsDataOfEachCompleteFrame() throws {
        var splitter = SSEFrameSplitter()
        let frames = try splitter.feed(Data("event: state\ndata: {\"a\":1}\n\nevent: state\ndata: {\"a\":2}\n\n".utf8))
        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{\"a\":2}"])
    }

    func testBuffersPartialFrameAcrossFeeds() throws {
        var splitter = SSEFrameSplitter()
        XCTAssertEqual(try splitter.feed(Data("event: state\ndata: {\"a\"".utf8)), [])
        XCTAssertEqual(try splitter.feed(Data(":1}\n".utf8)), [])
        let frames = try splitter.feed(Data("\n".utf8))
        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}"])
    }

    func testJoinsMultipleDataLinesAndIgnoresCommentsAndCRLF() throws {
        var splitter = SSEFrameSplitter()
        let frames = try splitter.feed(Data(": keepalive\r\ndata: line1\r\ndata:line2\r\n\r\n".utf8))
        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, ["line1\nline2"])
    }

    func testFrameWithoutDataYieldsNothing() throws {
        var splitter = SSEFrameSplitter()
        XCTAssertEqual(try splitter.feed(Data("event: state\n\n".utf8)), [])
    }

    func testRejectsOversizedFrame() {
        var splitter = SSEFrameSplitter()
        let big = Data("data: ".utf8) + Data(repeating: UInt8(ascii: "x"), count: SSEFrameSplitter.maxFrameBytes + 1)
        XCTAssertThrowsError(try splitter.feed(big)) { error in
            XCTAssertEqual(error as? SSEError, .frameTooLarge)
        }
    }
}

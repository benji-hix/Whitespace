// Tests/WhitespaceTests/FileBufferTests.swift
import XCTest
@testable import Whitespace

final class FileBufferTests: XCTestCase {
    func testNewBufferIsDirtyFalseWithNoURL() {
        let buf = FileBuffer(url: nil, text: "hello")
        XCTAssertFalse(buf.isDirty)
        XCTAssertNil(buf.url)
    }

    func testDisplayName_untitled() {
        let buf = FileBuffer(url: nil, text: "")
        XCTAssertEqual(buf.displayName, "Untitled")
    }

    func testDisplayName_fromURL() {
        let url = URL(fileURLWithPath: "/tmp/chapter-one.txt")
        let buf = FileBuffer(url: url, text: "")
        XCTAssertEqual(buf.displayName, "chapter-one.txt")
    }
}

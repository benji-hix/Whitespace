// Tests/WhitespaceTests/WhitespaceDocumentTests.swift
import XCTest
import UniformTypeIdentifiers
@testable import Whitespace

final class WhitespaceDocumentTests: XCTestCase {
    func testNewDocumentIsEmptyPlainText() {
        let doc = WhitespaceDocument()
        XCTAssertEqual(doc.text, "")
        XCTAssertEqual(doc.contentType, .plainText)
    }

    func testReadPlainTextUTF8() throws {
        let data = "hello world".data(using: .utf8)!
        let doc = try WhitespaceDocument(data: data, type: .plainText)
        XCTAssertEqual(doc.text, "hello world")
        XCTAssertEqual(doc.contentType, .plainText)
    }

    func testReadMarkdown() throws {
        let data = "# Heading\n\nBody.".data(using: .utf8)!
        let markdown = UTType("net.daringfireball.markdown")!
        let doc = try WhitespaceDocument(data: data, type: markdown)
        XCTAssertEqual(doc.text, "# Heading\n\nBody.")
        XCTAssertEqual(doc.contentType, markdown)
    }

    func testReadFallsBackToLatin1WhenNotUTF8() throws {
        // 0xE9 is "é" in Latin-1, invalid as a standalone UTF-8 byte.
        let data = Data([0x68, 0xE9, 0x6C, 0x6C, 0x6F]) // "héllo" Latin-1
        let doc = try WhitespaceDocument(data: data, type: .plainText)
        XCTAssertEqual(doc.text, "héllo")
    }

    func testReadEmptyData() throws {
        let doc = try WhitespaceDocument(data: Data(), type: .plainText)
        XCTAssertEqual(doc.text, "")
    }

    func testWriteRoundtripPlainText() throws {
        var doc = WhitespaceDocument()
        doc.text = "round trip"
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "round trip")
    }

    func testWriteRoundtripMarkdown() throws {
        let markdown = UTType("net.daringfireball.markdown")!
        let doc = WhitespaceDocument(text: "# Hi", contentType: markdown)
        let data = try doc.encodedData(for: markdown)
        XCTAssertEqual(String(data: data, encoding: .utf8), "# Hi")
    }

    func testWritableContentTypesPlainTextFirst() {
        XCTAssertEqual(WhitespaceDocument.writableContentTypes.first, .plainText)
        XCTAssertTrue(WhitespaceDocument.writableContentTypes.contains(WhitespaceDocument.markdownType))
    }

    func testReadableContentTypesIncludesMarkdown() {
        XCTAssertTrue(WhitespaceDocument.readableContentTypes.contains(WhitespaceDocument.markdownType))
        XCTAssertTrue(WhitespaceDocument.readableContentTypes.contains(.plainText))
    }
}

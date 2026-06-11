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
        let doc = WhitespaceDocument(text: "round trip")
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "round trip")
    }

    // MARK: - Formatting (styled runs)

    private var markdown: UTType { WhitespaceDocument.markdownType }

    func testReadMarkdownDecodesFormattingIntoRuns() throws {
        let data = "plain **bold** *lean*".data(using: .utf8)!
        let doc = try WhitespaceDocument(data: data, type: markdown)
        XCTAssertEqual(doc.runs, [
            StyledRun(text: "plain ", bold: false, italic: false, underline: false),
            StyledRun(text: "bold", bold: true, italic: false, underline: false),
            StyledRun(text: " ", bold: false, italic: false, underline: false),
            StyledRun(text: "lean", bold: false, italic: true, underline: false),
        ])
        XCTAssertEqual(doc.text, "plain bold lean")
    }

    func testWriteMarkdownEncodesRuns() throws {
        let doc = WhitespaceDocument(
            runs: [
                StyledRun(text: "say ", bold: false, italic: false, underline: false),
                StyledRun(text: "it", bold: true, italic: false, underline: false),
            ],
            contentType: markdown
        )
        let data = try doc.encodedData(for: markdown)
        XCTAssertEqual(String(data: data, encoding: .utf8), "say **it**")
    }

    func testWritePlainTextFlattensFormatting() throws {
        let doc = WhitespaceDocument(
            runs: [StyledRun(text: "loud", bold: true, italic: false, underline: false)],
            contentType: .plainText
        )
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "loud")
    }

    func testReadPlainTextNeverCreatesFormatting() throws {
        let data = "not **bold** here".data(using: .utf8)!
        let doc = try WhitespaceDocument(data: data, type: .plainText)
        XCTAssertEqual(doc.runs, [
            StyledRun(text: "not **bold** here", bold: false, italic: false, underline: false)
        ])
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

import XCTest
import UniformTypeIdentifiers
@testable import Whitespace

@MainActor
final class WhitespaceDocumentTests: XCTestCase {
    private var markdown: UTType { WhitespaceDocument.markdownType }

    private func read(_ string: String, as type: UTType) throws -> WhitespaceDocument {
        try read(Data(string.utf8), as: type)
    }

    private func read(_ data: Data, as type: UTType) throws -> WhitespaceDocument {
        let doc = WhitespaceDocument()
        doc.fileType = type.identifier
        try doc.read(from: data, ofType: type.identifier)
        return doc
    }

    /// NSDocument types a new document from the controller's default, which
    /// follows Settings ▸ Documents ▸ New Files.
    func testNewDocumentIsEmptyAndTakesTheDefaultType() {
        let doc = WhitespaceDocument()
        XCTAssertEqual(doc.textStorage.string, "")
        XCTAssertEqual(doc.fileType, NSDocumentController.shared.defaultType)
    }

    func testShellInstallsTheWhitespaceDocumentController() {
        XCTAssertTrue(NSDocumentController.shared is WhitespaceDocumentController)
    }

    func testReadPlainTextUTF8() throws {
        let doc = try read("hello world", as: .plainText)
        XCTAssertEqual(doc.textStorage.string, "hello world")
        XCTAssertEqual(doc.contentType, .plainText)
    }

    func testReadMarkdown() throws {
        let doc = try read("# Heading\n\nBody.", as: markdown)
        XCTAssertEqual(doc.textStorage.string, "# Heading\n\nBody.")
        XCTAssertEqual(doc.contentType, markdown)
    }

    func testReadFallsBackToLatin1WhenNotUTF8() throws {
        // 0xE9 is "é" in Latin-1, invalid as a standalone UTF-8 byte.
        let data = Data([0x68, 0xE9, 0x6C, 0x6C, 0x6F]) // "héllo" Latin-1
        let doc = try read(data, as: .plainText)
        XCTAssertEqual(doc.textStorage.string, "héllo")
    }

    func testReadEmptyData() throws {
        let doc = try read(Data(), as: .plainText)
        XCTAssertEqual(doc.textStorage.string, "")
    }

    func testWriteRoundtripPlainText() throws {
        let doc = makeDocument(runs: [StyledRun(text: "round trip", bold: false, italic: false)])
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "round trip")
    }

    // MARK: - Formatting (styled runs)

    func testReadMarkdownDecodesFormattingIntoStorage() throws {
        let doc = try read("plain **bold** *lean*", as: markdown)
        XCTAssertEqual(doc.runs, [
            StyledRun(text: "plain ", bold: false, italic: false),
            StyledRun(text: "bold", bold: true, italic: false),
            StyledRun(text: " ", bold: false, italic: false),
            StyledRun(text: "lean", bold: false, italic: true),
        ])
        XCTAssertEqual(doc.textStorage.string, "plain bold lean")
    }

    func testWriteMarkdownEncodesRuns() throws {
        let doc = makeDocument(runs: [
            StyledRun(text: "say ", bold: false, italic: false),
            StyledRun(text: "it", bold: true, italic: false),
        ], type: markdown)
        let data = try doc.encodedData(for: markdown)
        XCTAssertEqual(String(data: data, encoding: .utf8), "say **it**")
    }

    func testWritePlainTextFlattensFormatting() throws {
        let doc = makeDocument(runs: [StyledRun(text: "loud", bold: true, italic: false)])
        let data = try doc.encodedData(for: .plainText)
        XCTAssertEqual(String(data: data, encoding: .utf8), "loud")
    }

    func testReadPlainTextNeverCreatesFormatting() throws {
        let doc = try read("not **bold** here", as: .plainText)
        XCTAssertEqual(doc.runs, [
            StyledRun(text: "not **bold** here", bold: false, italic: false)
        ])
    }

    func testWriteRoundtripMarkdown() throws {
        let doc = makeDocument(runs: [StyledRun(text: "# Hi", bold: false, italic: false)], type: markdown)
        let data = try doc.encodedData(for: markdown)
        XCTAssertEqual(String(data: data, encoding: .utf8), "# Hi")
    }

    // MARK: - Types

    func testNewUntitledTypeFollowsNewFilesPreference() {
        let suite = "test-document-controller"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let type = { WhitespaceDocumentController.defaultTypeIdentifier(defaults: defaults) }

        XCTAssertEqual(type(), markdown.identifier, "markdown is the default")

        defaults.set(NewDocumentType.plainText.rawValue, forKey: NewDocumentType.defaultsKey)
        XCTAssertEqual(type(), UTType.plainText.identifier)

        defaults.set(NewDocumentType.markdown.rawValue, forKey: NewDocumentType.defaultsKey)
        XCTAssertEqual(type(), markdown.identifier)
    }

    func testSavePanelOffersExactlyMarkdownAndPlainText() {
        XCTAssertEqual(WhitespaceDocument().writableTypes(for: .saveAsOperation),
                       [markdown.identifier, UTType.plainText.identifier])
    }

    func testReadableTypesIncludeMarkdownAndPlainText() {
        XCTAssertTrue(WhitespaceDocument.readableTypes.contains(markdown.identifier))
        XCTAssertTrue(WhitespaceDocument.readableTypes.contains(UTType.plainText.identifier))
    }
}

// Tests/WhitespaceTests/ZenTextViewSetUpTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Pins the editor's setup order on a document opened in the dark theme.
/// `applyFont` replaces `typingAttributes` wholesale, so when colour was
/// applied first it was dropped, and loaded content drew in the default black.
/// `setUp` applies font, then colour, to the content already in the storage.
@MainActor
final class ZenTextViewSetUpTests: XCTestCase {
    private let dark = Theme.dark

    private func openInDarkTheme(_ markdown: String) throws -> ZenTextView {
        let doc = WhitespaceDocument()
        doc.fileType = WhitespaceDocument.markdownType.identifier
        try doc.read(from: Data(markdown.utf8), ofType: WhitespaceDocument.markdownType.identifier)
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textStorage: doc.textStorage)
        tv.setUp(fontSize: 18, lineHeightMultiple: 1.6,
                 text: dark.textColor, cursor: dark.cursorColor, selection: dark.selectionColor)
        return tv
    }

    func testEveryLoadedCharacterCarriesTheThemeColour() throws {
        let tv = try openInDarkTheme("plain **bold** *lean* ***both***")
        let storage = try XCTUnwrap(tv.textStorage)
        var uncoloured: [NSRange] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if (value as? NSColor) != dark.textColor { uncoloured.append(range) }
        }
        XCTAssertEqual(uncoloured, [], "every loaded character should draw in the theme's text colour")
        XCTAssertEqual(tv.styledRuns.filter { $0.bold || $0.italic }.count, 3,
                       "setup must restyle without losing bold or italic")
    }

    func testTypingAttributesHoldFontAndColour() throws {
        let tv = try openInDarkTheme("plain")
        XCTAssertEqual(tv.typingAttributes[.foregroundColor] as? NSColor, dark.textColor)
        let font = try XCTUnwrap(tv.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.fontName, WhitespaceFont.regular)
        XCTAssertEqual(font.pointSize, 18)
    }
}

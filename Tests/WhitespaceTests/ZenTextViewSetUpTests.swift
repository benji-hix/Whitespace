// Tests/WhitespaceTests/ZenTextViewSetUpTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Pins the editor's colour through setup and font-size changes, in the dark
/// theme. `applyFont` once replaced `typingAttributes` wholesale, so colour
/// applied before it was dropped: loaded content drew in the default black,
/// and so did text typed after ⌘+/⌘−. `setUp` applies font, then colour, and
/// `applyFont` now merges.
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

    /// ⌘+ and ⌘− end in `applyFont` with the new size. Text typed after them
    /// must still draw in the theme colour, not the default black.
    func testTextTypedAfterAFontSizeChangeKeepsTheThemeColour() throws {
        try assertTypingAfterFontSizeChangeKeepsColour(in: "plain")
    }

    /// An empty document has no neighbouring character for typing to take
    /// its colour from, so the typing attributes are all there is.
    func testTextTypedInAnEmptyDocumentAfterAFontSizeChangeKeepsTheThemeColour() throws {
        try assertTypingAfterFontSizeChangeKeepsColour(in: "")
    }

    /// ⌘B or ⌘I with nothing selected arms a face for the next typing. A size
    /// change in between must keep that face, only at the new size.
    func testArmedFaceSurvivesAFontSizeChange() throws {
        let tv = try openInDarkTheme("")
        let armed = try XCTUnwrap(NSFont(name: WhitespaceFont.boldItalic, size: 18))
        tv.typingAttributes[.font] = armed
        tv.applyFont(size: 19, lineHeightMultiple: 1.6)

        tv.insertText("loud", replacementRange: NSRange(location: 0, length: 0))
        let font = try XCTUnwrap(tv.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.fontName, WhitespaceFont.boldItalic, "the armed face was dropped")
        XCTAssertEqual(font.pointSize, 19)
        XCTAssertEqual(tv.styledRuns, [StyledRun(text: "loud", bold: true, italic: true)])
    }

    private func assertTypingAfterFontSizeChangeKeepsColour(
        in markdown: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let tv = try openInDarkTheme(markdown)
        let storage = try XCTUnwrap(tv.textStorage)
        let end = storage.length
        // Caret first, then the size change, then typing, as a writer would:
        // a selection change after `applyFont` could refresh the typing
        // attributes from the text and hide the bug.
        tv.setSelectedRange(NSRange(location: end, length: 0))
        tv.applyFont(size: 19, lineHeightMultiple: 1.6)
        XCTAssertEqual(tv.typingAttributes[.foregroundColor] as? NSColor, dark.textColor,
                       "typing attributes lost the colour", file: file, line: line)

        tv.insertText("typed", replacementRange: NSRange(location: end, length: 0))
        let typed = storage.attribute(.foregroundColor, at: end, effectiveRange: nil) as? NSColor
        XCTAssertEqual(typed, dark.textColor,
                       "text typed after ⌘+ should draw in the theme's text colour", file: file, line: line)
        let font = storage.attribute(.font, at: end, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 19, file: file, line: line)
    }

    func testTypingAttributesHoldFontAndColour() throws {
        let tv = try openInDarkTheme("plain")
        XCTAssertEqual(tv.typingAttributes[.foregroundColor] as? NSColor, dark.textColor)
        let font = try XCTUnwrap(tv.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.fontName, WhitespaceFont.regular)
        XCTAssertEqual(font.pointSize, 18)
    }
}

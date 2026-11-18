// Tests/WhitespaceTests/ZenTextViewSetUpTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Pins the editor's setup order. Content is built from `typingAttributes`,
/// so by the time it is built they must carry both the font and the theme's
/// text colour. When `applyFont` ran after `applyColors` and replaced the
/// typing attributes wholesale, a document opened in the dark theme was built
/// with no foreground colour and drew in the default black.
@MainActor
final class ZenTextViewSetUpTests: XCTestCase {

    private let dark = Theme.dark

    private func makeView(runs: [StyledRun]) -> ZenTextView {
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        tv.setUp(
            fontSize: 18, lineHeightMultiple: 1.6,
            text: dark.textColor, cursor: dark.cursorColor, selection: dark.selectionColor,
            runs: runs
        )
        return tv
    }

    func testInitialContentCarriesThemeTextColour() throws {
        let tv = makeView(runs: [
            StyledRun(text: "plain ", bold: false, italic: false),
            StyledRun(text: "bold", bold: true, italic: false),
        ])
        let storage = try XCTUnwrap(tv.textStorage)
        var uncoloured: [NSRange] = []
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if (value as? NSColor) != dark.textColor { uncoloured.append(range) }
        }
        XCTAssertEqual(uncoloured, [], "every loaded character should draw in the theme's text colour")
    }

    func testTypingAttributesCarryFontAndColourAfterSetUp() throws {
        let tv = makeView(runs: [])
        XCTAssertEqual(tv.typingAttributes[.foregroundColor] as? NSColor, dark.textColor)
        let font = try XCTUnwrap(tv.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.pointSize, 18)
        XCTAssertNotNil(tv.typingAttributes[.paragraphStyle])
    }

    /// ⌘+/⌘− call `applyFont` on a live editor; the colour must survive it, or
    /// the next typed character draws black in the dark theme.
    func testFontSizeChangeKeepsTypingColour() {
        let tv = makeView(runs: [])
        tv.applyFont(size: 22, lineHeightMultiple: 1.6)
        tv.insertText("x", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(tv.typingAttributes[.foregroundColor] as? NSColor, dark.textColor)
        XCTAssertEqual(tv.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       dark.textColor)
        XCTAssertEqual((tv.typingAttributes[.font] as? NSFont)?.pointSize, 22)
    }
}

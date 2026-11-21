// Tests/WhitespaceTests/ZenTextViewCaretBaselineTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Characterization tests for caret geometry. **These do not catch the
/// baseline regression they were written for** — that was measured, not
/// assumed: with `ensureParagraphLayout` reverted to the original
/// `ensureLayout(for: caretRange)`, every test in this file still passed.
/// Forcing the failure by calling `invalidateLayout(for:)` first did not work
/// either; the TK2 queries re-run layout on demand.
///
/// The reason is in `ensureParagraphLayout`'s own diagnosis: the stale read
/// comes from the *viewport layout pass*, which only runs during a real draw
/// cycle in an on-screen window. An offscreen `NSWindow` settles layout
/// synchronously, so the window the bug lives in never opens here.
///
/// What these are worth: they pin the current caret geometry, so a future
/// change that breaks it outright (nil rect, wrong height, wrong line) fails
/// loudly, and `testCaretRectOnEmptyDocumentDoesNotTrap` covers a genuinely new
/// code path — `ensureParagraphLayout` steps back a location, which an empty
/// document does not have. The baseline fix itself is owner-verified on screen.
///
/// Hosted offscreen per the `ZenTextViewUndoTests` pattern.
@MainActor
final class ZenTextViewCaretBaselineTests: XCTestCase {
    private var window: NSWindow!
    private var textView: ZenTextView!

    override func setUp() {
        super.setUp()
        textView = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.documentView = textView
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scroll
        window.makeFirstResponder(textView)
    }

    override func tearDown() {
        window = nil
        textView = nil
        super.tearDown()
    }

    /// The caret rect once TK2 has no outstanding layout anywhere.
    private func settledCaretRect() -> NSRect? {
        guard let tlm = textView.textLayoutManager else { return nil }
        tlm.ensureLayout(for: tlm.documentRange)
        return textView.currentCursorBarRect()
    }

    private func assertCaretMatchesSettledLayout(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let immediate = textView.currentCursorBarRect() else {
            return XCTFail("no caret rect — \(message)", file: file, line: line)
        }
        guard let settled = settledCaretRect() else {
            return XCTFail("no settled caret rect — \(message)", file: file, line: line)
        }
        // Sub-point drift is rounding, not staleness; the defect displaced the
        // caret by a fraction of a *line*, which at 18pt is several points.
        XCTAssertEqual(immediate.origin.y, settled.origin.y, accuracy: 0.5,
                       "caret top — \(message)", file: file, line: line)
        XCTAssertEqual(immediate.height, settled.height, accuracy: 0.5,
                       "caret height — \(message)", file: file, line: line)
    }

    // MARK: - A font-size change moves the drawn caret

    // ⌘+/⌘− restyle the storage without an edit or a selection change, so
    // nothing refreshed the drawn caret: it stayed where the old size put it
    // until the next blink tick, up to 0.53 s. These check the refresh is
    // asked for; on-screen timing is beyond an offscreen window (see above).

    private func assertDrawnCaretFollowsFontSizeChange(
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        textView.applyFont(size: 18, lineHeightMultiple: 1.6)
        let end = textView.string.utf16.count
        textView.setSelectedRange(NSRange(location: end, length: 0))
        guard let before = textView.displayedCursorFrame else {
            return XCTFail("caret not drawn before the change — \(message)", file: file, line: line)
        }

        textView.applyFont(size: 36, lineHeightMultiple: 1.6)

        guard let drawn = textView.displayedCursorFrame,
              let expected = textView.currentCursorBarRect() else {
            return XCTFail("caret not drawn after the change — \(message)", file: file, line: line)
        }
        XCTAssertNotEqual(expected, before, "the size change should move the caret — \(message)",
                          file: file, line: line)
        XCTAssertEqual(drawn, expected, "drawn caret is stale — \(message)", file: file, line: line)
    }

    func testDrawnCaretFollowsAFontSizeChange() {
        textView.insertText("first paragraph\nsecond", replacementRange: NSRange(location: 0, length: 0))
        assertDrawnCaretFollowsFontSizeChange("caret at end of text")
    }

    func testDrawnCaretFollowsAFontSizeChangeInAnEmptyDocument() {
        assertDrawnCaretFollowsFontSizeChange("empty document")
    }

    /// The reported trigger: the first glyph typed on a fresh line.
    func testCaretSitsOnBaselineForFirstGlyphOfFreshLine() {
        textView.insertText("first line", replacementRange: NSRange(location: 0, length: 0))
        textView.insertText("\n", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))

        assertCaretMatchesSettledLayout("first glyph on a fresh line")
    }

    /// The second reported trigger: ⌘Z.
    func testCaretSitsOnBaselineAfterUndo() {
        textView.insertText("first line", replacementRange: NSRange(location: 0, length: 0))
        textView.insertText("\n", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("second", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        textView.undoManager?.undo()

        assertCaretMatchesSettledLayout("after undo")
    }

    /// Several lines deep, where a stale fragment origin has more room to be
    /// wrong than on line two.
    func testCaretSitsOnBaselineDeepInDocument() {
        for i in 1...8 {
            textView.insertText("line \(i)\n", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        }
        textView.insertText("t", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))

        assertCaretMatchesSettledLayout("ninth line")
    }

    /// `ensureParagraphLayout` steps back one location when the caret is at
    /// end-of-text, where `textLayoutFragment(for:)` returns nil. An empty
    /// document has no previous location at all — it must not trap.
    func testCaretRectOnEmptyDocumentDoesNotTrap() {
        XCTAssertNotNil(textView.textLayoutManager)
        _ = textView.currentCursorBarRect()
    }

    /// The caret spans the font's typographic extent — ascender above the
    /// baseline, descender below. Measured against AppKit's own
    /// `NSTextInsertionIndicator` on a stock `NSTextView`, which fills the line
    /// box exactly: at CrimsonPro-Light 72pt it ran 65.0 above the baseline
    /// (ascender 64.547) and 15.0 below (descender 15.469).
    ///
    /// Unlike the staleness tests above, this one discriminates: the previous
    /// fixed 2pt below-baseline extension gives `ascender + 2`, which is short
    /// by `|descender| - 2` — 1.87pt at 18pt Crimson — and fails here.
    func testCaretSpansAscenderToDescender() throws {
        textView.applyFont(size: 18, lineHeightMultiple: 1.6)
        textView.insertText("typography", replacementRange: NSRange(location: 0, length: 0))

        let font = try XCTUnwrap(textView.typingAttributes[.font] as? NSFont)
        let rect = try XCTUnwrap(textView.currentCursorBarRect())

        // Both ends are independently rounded, so allow a point of slack.
        XCTAssertEqual(rect.height, font.ascender + abs(font.descender), accuracy: 1.0,
                       "caret should span ascender..descender, not stop short of the descender")
    }

    /// Line spacing must not change the caret: `lineHeightMultiple` inflates the
    /// line fragment (1.6 turns a 20pt line box into ~32pt), and a caret that
    /// tracked it would read as a selection block rather than an insertion point.
    func testCaretHeightIgnoresLineHeightMultiple() throws {
        textView.insertText("typography", replacementRange: NSRange(location: 0, length: 0))

        textView.applyFont(size: 18, lineHeightMultiple: 1.0)
        let tight = try XCTUnwrap(textView.currentCursorBarRect()).height
        textView.applyFont(size: 18, lineHeightMultiple: 1.6)
        let loose = try XCTUnwrap(textView.currentCursorBarRect()).height

        XCTAssertEqual(tight, loose, accuracy: 1.0,
                       "caret height tracked line spacing instead of the font")
    }

    /// Explicitly invalidating layout before the read was the strongest attempt
    /// at reproducing the defect headlessly. It does not reproduce it either —
    /// TK2 re-runs layout on demand inside the queries — so this is kept as
    /// characterization, not as the regression guard it was meant to be.
    func testCaretGeometryIsCorrectWhileParagraphLayoutIsInvalid() throws {
        textView.insertText("first line", replacementRange: NSRange(location: 0, length: 0))
        textView.insertText("\n", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: textView.string.utf16.count, length: 0))

        let tlm = try XCTUnwrap(textView.textLayoutManager)
        tlm.ensureLayout(for: tlm.documentRange)
        let reference = try XCTUnwrap(textView.currentCursorBarRect())

        tlm.invalidateLayout(for: tlm.documentRange)
        let afterInvalidation = try XCTUnwrap(textView.currentCursorBarRect())

        XCTAssertEqual(afterInvalidation.origin.y, reference.origin.y, accuracy: 0.5,
                       "caret top drifted when read against invalidated layout")
        XCTAssertEqual(afterInvalidation.height, reference.height, accuracy: 0.5,
                       "caret height drifted when read against invalidated layout")
    }
}

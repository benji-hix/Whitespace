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

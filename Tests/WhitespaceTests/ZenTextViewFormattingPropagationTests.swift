// Tests/WhitespaceTests/ZenTextViewFormattingPropagationTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// ⌘B / ⌘I on a *selection* is an attribute-only edit. It still has to go
/// through NSTextView's change contract, or the bold exists only in the text
/// storage: the document's runs never hear about it, so it is missing from the
/// save, missing from the flatten warning's formatting check, and not undoable.
///
/// The pre-existing coverage pressed ⌘B with no selection and then typed, which
/// hides the bug — `insertText` fires `didChangeText` for its own reasons.
/// Hosted in a window because undo needs an NSUndoManager from the responder
/// chain, per `ZenTextViewUndoTests`.
@MainActor
final class ZenTextViewFormattingPropagationTests: XCTestCase, NSTextViewDelegate {
    private var window: NSWindow!
    private var textView: ZenTextView!
    private var changeCount = 0

    func textDidChange(_ notification: Notification) {
        changeCount += 1
    }

    override func setUp() {
        super.setUp()
        let frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView = ZenTextView(frame: frame)
        let scroll = NSScrollView(frame: frame)
        scroll.documentView = textView
        window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scroll
        window.makeFirstResponder(textView)
        textView.applyFont(size: 18, lineHeightMultiple: 1.6)
        textView.delegate = self
        changeCount = 0
    }

    override func tearDown() {
        window = nil; textView = nil
        super.tearDown()
    }

    private func pressCommand(_ character: String, keyCode: UInt16) {
        textView.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!)
    }

    private func selectAllAndBold() {
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))
        pressCommand("b", keyCode: 11)
    }

    /// The regression: the storage went bold but the delegate never fired, so
    /// the document kept plain runs and saved them.
    func testBoldOnASelectionNotifiesTheDelegate() {
        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        let afterTyping = changeCount

        selectAllAndBold()

        XCTAssertEqual(textView.styledRuns,
                       [StyledRun(text: "hello", bold: true, italic: false)],
                       "storage should carry the bold")
        XCTAssertGreaterThan(changeCount, afterTyping,
                             "⌘B on a selection must notify the delegate — that is the only route into the document")
    }

    func testItalicOnASelectionNotifiesTheDelegate() {
        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        let afterTyping = changeCount

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        pressCommand("i", keyCode: 34)

        XCTAssertEqual(textView.styledRuns,
                       [StyledRun(text: "hello", bold: false, italic: true)])
        XCTAssertGreaterThan(changeCount, afterTyping)
    }

    /// Plain-text documents consume the chord silently (ARCHITECTURE.md §2), so
    /// nothing should change and nothing should be reported.
    func testFormattingChordIsInertInPlainTextDocuments() {
        textView.formattingEnabled = false
        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        let afterTyping = changeCount

        selectAllAndBold()

        XCTAssertEqual(textView.styledRuns, [StyledRun(text: "hello", bold: false, italic: false)])
        XCTAssertEqual(changeCount, afterTyping, "an inert chord must not report a change")
    }
}

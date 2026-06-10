// Tests/WhitespaceTests/ZenTextViewUndoTests.swift
import XCTest
import AppKit
@testable import Whitespace

/// Undo requires a window-provided NSUndoManager reachable through the
/// responder chain, so these tests host the view in an offscreen window
/// the way SwiftUI hosts it in production.
@MainActor
final class ZenTextViewUndoTests: XCTestCase {
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

    func testUndoIsEnabled() {
        XCTAssertTrue(textView.allowsUndo)
    }

    func testTypingCanBeUndone() {
        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(textView.string, "hello")
        XCTAssertEqual(textView.undoManager?.canUndo, true)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "")
    }

    func testUndoRedoRoundTrip() {
        textView.insertText("draft", replacementRange: NSRange(location: 0, length: 0))
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "")

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "draft")
    }
}

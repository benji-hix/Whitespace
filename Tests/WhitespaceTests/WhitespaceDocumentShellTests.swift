// Tests/WhitespaceTests/WhitespaceDocumentShellTests.swift
import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Whitespace

/// The document as NSDocument drives it: the storage is the truth, saves read
/// it, revert replaces it, and edits reach the change count.
///
/// Every document that can be edited gets a temporary file URL and is closed
/// in tearDown. An edited untitled document would autosave into the owner's
/// real ~/Library/Autosave Information, which the test host shares.
@MainActor
final class WhitespaceDocumentShellTests: XCTestCase {
    private var markdown: UTType { WhitespaceDocument.markdownType }

    private func tempURL(_ ext: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shell-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A markdown document read from a real temp file, so autosave has a home.
    private func openFile(_ contents: String, type: UTType? = nil) throws -> (WhitespaceDocument, URL) {
        let type = type ?? markdown
        let url = tempURL(type == markdown ? "md" : "txt")
        try Data(contents.utf8).write(to: url)
        let doc = try WhitespaceDocument(contentsOf: url, ofType: type.identifier)
        addTeardownBlock { @MainActor in doc.close() }
        return (doc, url)
    }

    /// An editor wired to the document the way the window wires it.
    private func attachEditor(to doc: WhitespaceDocument) -> ZenTextView {
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textStorage: doc.textStorage)
        tv.delegate = doc
        tv.formattingEnabled = doc.isMarkdown
        tv.setUp(fontSize: 18, lineHeightMultiple: 1.6, text: .black, cursor: .black, selection: .gray)
        doc.editor = tv
        return tv
    }

    /// The production path: the document's own window and hosted editor.
    private func openInWindow(_ contents: String) throws -> (WhitespaceDocument, ZenTextView) {
        let (doc, _) = try openFile(contents)
        doc.makeWindowControllers()
        let window = try XCTUnwrap(doc.windowControllers.first?.window)
        window.contentView?.layoutSubtreeIfNeeded()
        spinRunLoop()
        let editor = try XCTUnwrap(doc.editor, "the hosted editor should register with its document")
        window.makeFirstResponder(editor)
        return (doc, editor)
    }

    /// Typing opens an automatic undo group that AppKit's event loop closes at
    /// the end of each event; NSDocument counts the edit when it closes. A test
    /// has no event loop, so it closes the group the same way.
    private func endEvent(_ doc: WhitespaceDocument) {
        if let undo = doc.undoManager, undo.groupingLevel > 0 { undo.endUndoGrouping() }
        spinRunLoop()
    }

    private func pressCommandB(_ tv: ZenTextView) {
        tv.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "b",
            charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11)!)
    }

    // MARK: - Reading and writing

    func testOpenLoadsStorageForMarkdownAndPlainText() throws {
        let (md, _) = try openFile("plain **bold**")
        XCTAssertEqual(md.runs, [StyledRun(text: "plain ", bold: false, italic: false),
                                 StyledRun(text: "bold", bold: true, italic: false)])
        let (txt, _) = try openFile("plain **bold**", type: .plainText)
        XCTAssertEqual(txt.textStorage.string, "plain **bold**")
        XCTAssertEqual(txt.runs.count, 1)
    }

    /// The bytes NSDocument writes come from the storage, encoded exactly as
    /// the old struct's `encodedData` did.
    func testStorageEditReachesTheSavedBytes() throws {
        let (doc, _) = try openFile("say ")
        let bold = try XCTUnwrap(NSFont(name: WhitespaceFont.bold, size: 18))
        doc.textStorage.append(NSAttributedString(string: "it", attributes: [.font: bold]))

        let md = try doc.data(ofType: markdown.identifier)
        XCTAssertEqual(String(data: md, encoding: .utf8), "say **it**")
        XCTAssertEqual(md, try doc.encodedData(for: markdown))
    }

    func testAutosaveInPlaceWritesTheStorage() throws {
        let (doc, url) = try openFile("old")
        let bold = try XCTUnwrap(NSFont(name: WhitespaceFont.bold, size: 18))
        doc.textStorage.append(NSAttributedString(string: " new", attributes: [.font: bold]))

        let saved = expectation(description: "autosave finished")
        doc.save(to: url, ofType: markdown.identifier, for: .autosaveInPlaceOperation) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 5)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old **new**")
    }

    func testRevertReplacesTheStorageAndRestylesTheEditor() throws {
        let (doc, url) = try openFile("*lean* text")
        let tv = attachEditor(to: doc)
        tv.insertText("junk ", replacementRange: NSRange(location: 0, length: 0))

        try doc.revert(toContentsOf: url, ofType: markdown.identifier)

        XCTAssertEqual(doc.runs, [StyledRun(text: "lean", bold: false, italic: true),
                                  StyledRun(text: " text", bold: false, italic: false)])
        XCTAssertEqual(tv.undoManager?.canUndo, false, "undo must not reach into the replaced content")
        let storage = doc.textStorage
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, _, _ in
            XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize, 18, "reverted content must take the editor's size")
            XCTAssertEqual(attrs[.foregroundColor] as? NSColor, .black, "and its colour")
            XCTAssertNotNil(attrs[.paragraphStyle])
        }
    }

    // MARK: - Change count

    /// ⌘B on a selection registers no undo under TextKit 2, so NSDocument would
    /// never hear of it; the document's delegate counts it instead.
    func testBoldOnASelectionMarksTheDocumentEdited() throws {
        let (doc, tv) = try openInWindow("hello")
        XCTAssertFalse(doc.isDocumentEdited)

        tv.setSelectedRange(NSRange(location: 0, length: 5))
        pressCommandB(tv)

        XCTAssertEqual(doc.runs, [StyledRun(text: "hello", bold: true, italic: false)])
        XCTAssertTrue(doc.isDocumentEdited)
    }

    /// Typing is counted through the undo manager only. Counting it a second
    /// time would leave the document dirty after undoing back to the save.
    func testTypingThenUndoingReturnsTheDocumentToClean() throws {
        let (doc, tv) = try openInWindow("hello")

        tv.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        endEvent(doc)
        XCTAssertTrue(doc.isDocumentEdited)

        tv.undoManager?.undo()
        endEvent(doc)
        XCTAssertEqual(doc.textStorage.string, "hello")
        XCTAssertFalse(doc.isDocumentEdited)
    }

    /// Appearance repaints rewrite attributes across the whole storage. They
    /// are not edits: no dirty mark, nothing to undo.
    func testThemeAndFontRepaintsAreNotEdits() throws {
        let (doc, _) = try openFile("hello **bold**")
        let tv = attachEditor(to: doc)

        tv.applyColors(text: .white, cursor: .white, selection: .darkGray)
        tv.applyFont(size: 24, lineHeightMultiple: 1.4)
        spinRunLoop()

        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertEqual(tv.undoManager?.canUndo, false)
    }

    // MARK: - Shell wiring

    /// The real window: the editor inside the hosting view edits the document's
    /// storage and undoes through the document's undo manager.
    func testWindowEditorSharesTheDocumentStorageAndUndoManager() throws {
        let (doc, editor) = try openInWindow("hello")
        XCTAssertTrue(editor.window === doc.windowControllers.first?.window)
        XCTAssertTrue(editor.textStorage === doc.textStorage)
        XCTAssertNotNil(editor.textLayoutManager, "must stay on TextKit 2")
        XCTAssertTrue(editor.undoManager === doc.undoManager)
    }

    func testFileTypeChangeSwitchesTheEditorFormattingMode() throws {
        let (doc, _) = try openFile("hello")
        let tv = attachEditor(to: doc)
        XCTAssertTrue(tv.formattingEnabled)

        doc.fileType = UTType.plainText.identifier
        XCTAssertFalse(tv.formattingEnabled)
        XCTAssertFalse(tv.isRichText)
    }

    /// Bold and italic are recognised by font name; if a face fails to
    /// resolve, formatting flattens on read and is saved flat.
    func testCrimsonProFacesResolve() {
        for name in [WhitespaceFont.regular, WhitespaceFont.italic, WhitespaceFont.bold, WhitespaceFont.boldItalic] {
            XCTAssertEqual(NSFont(name: name, size: 18)?.fontName, name)
        }
    }
}

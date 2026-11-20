import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Whitespace

/// Files the save would not write back byte for byte are protected: edits ask
/// first, and nothing is written over the original until the owner says so.
///
/// Every document gets a temporary file and is closed in teardown; see
/// `WhitespaceDocumentShellTests` for why.
@MainActor
final class WhitespaceDocumentProtectionTests: XCTestCase {
    private var markdown: UTType { WhitespaceDocument.markdownType }
    private let lossy = "see [the site](https://example.com) and **this**"

    private func tempURL(_ ext: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("protect-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func openFile(_ data: Data, type: UTType? = nil) throws -> (WhitespaceDocument, URL) {
        let type = type ?? markdown
        let url = tempURL(type == markdown ? "md" : "txt")
        try data.write(to: url)
        let doc = try WhitespaceDocument(contentsOf: url, ofType: type.identifier)
        addTeardownBlock { @MainActor in doc.close() }
        return (doc, url)
    }

    private func openFile(_ contents: String, type: UTType? = nil) throws -> (WhitespaceDocument, URL) {
        try openFile(Data(contents.utf8), type: type)
    }

    /// The document's own window and editor, with the sheet replaced by a
    /// recorder that answers `answer`.
    private func openInWindow(_ contents: String, answer: WhitespaceDocument.ProtectedEditChoice = .cancel)
        throws -> (WhitespaceDocument, ZenTextView, Prompts) {
        let (doc, _) = try openFile(contents)
        let prompts = Prompts(answer: answer)
        doc.askBeforeEditingProtected = { _, choose in prompts.count += 1; choose(prompts.answer) }
        doc.makeWindowControllers()
        let window = try XCTUnwrap(doc.windowControllers.first?.window)
        window.contentView?.layoutSubtreeIfNeeded()
        spinRunLoop()
        let editor = try XCTUnwrap(doc.editor)
        window.makeFirstResponder(editor)
        return (doc, editor, prompts)
    }

    final class Prompts {
        var count = 0
        var answer: WhitespaceDocument.ProtectedEditChoice
        init(answer: WhitespaceDocument.ProtectedEditChoice) { self.answer = answer }
    }

    /// An accepted edit, framed the way AppKit's event loop frames it.
    private func asOneEvent(_ doc: WhitespaceDocument, _ action: () -> Void) {
        let undo = doc.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
        undo.groupsByEvent = true
        spinRunLoop()
    }

    /// An edit the gate refuses. No explicit group: an empty one still counts
    /// as undoable and NSDocument would count it, which the app never does,
    /// because AppKit opens a group only when something registers. With
    /// grouping by event, anything that did register shows up in `canUndo`.
    private func refused(_ doc: WhitespaceDocument, _ action: () -> Void) {
        action()
        spinRunLoop()
        XCTAssertEqual(doc.undoManager?.canUndo, false, "a refused edit must register nothing")
    }

    private func typeKey(_ tv: ZenTextView, _ character: String, keyCode: UInt16) {
        tv.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: tv.window?.windowNumber ?? 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!)
    }

    private func chord(_ tv: ZenTextView, _ character: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) {
        tv.keyDown(with: NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!)
    }

    private func save(_ doc: WhitespaceDocument, to url: URL, as type: UTType? = nil,
                      _ operation: NSDocument.SaveOperationType) -> Error? {
        var result: Error?
        let done = expectation(description: "save finished")
        doc.save(to: url, ofType: (type ?? markdown).identifier, for: operation) { error in
            result = error
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    // MARK: - Reading

    func testLosslessFileIsNotProtected() throws {
        let (doc, _) = try openFile("plain **bold** *lean*\n")
        XCTAssertFalse(doc.isProtected)
    }

    func testLossyFileOpensReadableAndProtected() throws {
        let (doc, _) = try openFile(lossy)
        XCTAssertTrue(doc.isProtected)
        XCTAssertEqual(doc.textStorage.string, "see the site and this")
    }

    func testRevertReReadsProtection() throws {
        let (doc, url) = try openFile(lossy)
        doc.isProtected = false
        try doc.revert(toContentsOf: url, ofType: markdown.identifier)
        XCTAssertTrue(doc.isProtected)
    }

    // MARK: - Round trips through the storage

    /// BOM, CRLF and a trailing newline all come back byte for byte through
    /// read → storage → save, not only through the codec.
    func testFormatSurvivesASaveThroughTheStorage() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("one\r\n**two**\r\n".utf8)
        let (doc, url) = try openFile(original)
        XCTAssertFalse(doc.isProtected)
        XCTAssertEqual(doc.textStorage.string, "one\ntwo\n")

        doc.textStorage.append(NSAttributedString(string: "three\n"))
        XCTAssertNil(save(doc, to: url, .saveOperation))

        let expected = Data([0xEF, 0xBB, 0xBF]) + Data("one\r\n**two**\r\nthree\r\n".utf8)
        XCTAssertEqual(try Data(contentsOf: url), expected)
    }

    /// ARCHITECTURE §2 listed "a file's single trailing newline is dropped on
    /// first load". Measured through the document: it is not, for either type.
    func testTrailingNewlineSurvivesThroughTheDocument() throws {
        for type in [markdown, .plainText] {
            for text in ["abc\n", "abc\n\n"] {
                let (doc, _) = try openFile(text, type: type)
                XCTAssertEqual(try doc.encodedData(for: type), Data(text.utf8), "\(text.debugDescription) as \(type)")
            }
        }
    }

    // MARK: - Write refusal (the guarantee)

    func testProtectedDocumentNeverWritesOverItsOriginal() throws {
        let (doc, url) = try openFile(lossy)
        let original = try Data(contentsOf: url)
        doc.textStorage.append(NSAttributedString(string: " more"))

        for operation in [NSDocument.SaveOperationType.autosaveInPlaceOperation, .saveOperation, .saveAsOperation] {
            let error = save(doc, to: url, operation)
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission, "\(operation)")
            XCTAssertEqual(try Data(contentsOf: url), original, "the bytes must be untouched after \(operation)")
        }
        XCTAssertTrue(doc.isProtected)
    }

    /// The same file under a differently cased path (the volume ignores
    /// case) is still the original. A symlink needs no such check: the safe
    /// save replaces the link, not the file it points to.
    func testRefusalFollowsTheFileNotThePath() throws {
        let (doc, url) = try openFile(lossy)
        let original = try Data(contentsOf: url)
        let recased = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent.uppercased())
        try XCTSkipUnless(FileManager.default.fileExists(atPath: recased.path), "case-sensitive volume")

        XCTAssertNotNil(save(doc, to: recased, .saveToOperation))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSaveAsElsewhereIsAllowedAndEndsProtection() throws {
        let (doc, url) = try openFile(lossy)
        let original = try Data(contentsOf: url)
        let elsewhere = tempURL("md")

        XCTAssertNil(save(doc, to: elsewhere, .saveAsOperation))

        XCTAssertEqual(String(decoding: try Data(contentsOf: elsewhere), as: UTF8.self), "see the site and **this**")
        XCTAssertEqual(try Data(contentsOf: url), original, "the original stays as it was")
        XCTAssertFalse(doc.isProtected, "the document now refers to a file it wrote itself")
    }

    func testExportElsewhereKeepsProtection() throws {
        let (doc, _) = try openFile(lossy)
        XCTAssertNil(save(doc, to: tempURL("md"), .saveToOperation))
        XCTAssertTrue(doc.isProtected, "the document still refers to the original")
    }

    func testEditAnywayLetsTheSaveFlatten() throws {
        let (doc, url) = try openFile(lossy)
        doc.isProtected = false
        XCTAssertNil(save(doc, to: url, .saveOperation))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "see the site and **this**")
    }

    // MARK: - Edit gate (the UX)

    func testTypingAsksAndIsDroppedOnCancel() throws {
        let (doc, tv, prompts) = try openInWindow(lossy, answer: .cancel)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        refused(doc) { typeKey(tv, "x", keyCode: 7) }

        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(doc.textStorage.string, "see the site and this")
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertTrue(doc.isProtected, "Cancel asks again next time")

        refused(doc) { typeKey(tv, "x", keyCode: 7) }
        XCTAssertEqual(prompts.count, 2)
    }

    func testEditAnywayIsAskedOnceThenEditsGoThrough() throws {
        let (doc, tv, prompts) = try openInWindow(lossy, answer: .editAnyway)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        refused(doc) { typeKey(tv, "x", keyCode: 7) }
        XCTAssertFalse(doc.isProtected)
        XCTAssertEqual(doc.textStorage.string, "see the site and this", "the asking keystroke is dropped")

        asOneEvent(doc) { typeKey(tv, "x", keyCode: 7) }
        asOneEvent(doc) { typeKey(tv, "y", keyCode: 16) }
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(doc.textStorage.string, "xysee the site and this")
        XCTAssertTrue(doc.isDocumentEdited)
    }

    func testPasteAsks() throws {
        let (doc, tv, prompts) = try openInWindow(lossy)
        let board = NSPasteboard(name: NSPasteboard.Name("whitespace-test-\(UUID().uuidString)"))
        addTeardownBlock { @MainActor in board.releaseGlobally() }
        board.clearContents()
        board.setString("pasted ", forType: .string)
        tv.setSelectedRange(NSRange(location: 0, length: 0))

        refused(doc) { _ = tv.readSelection(from: board) }

        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(doc.textStorage.string, "see the site and this")
    }

    func testBoldOnASelectionAsksAndDoesNotMarkEdited() throws {
        let (doc, tv, prompts) = try openInWindow(lossy)
        tv.setSelectedRange(NSRange(location: 0, length: 3))
        refused(doc) { chord(tv, "b", keyCode: 11, [.command]) }

        XCTAssertEqual(prompts.count, 1)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertEqual(doc.runs.first, StyledRun(text: "see the site and ", bold: false, italic: false))
    }

    /// Risk B3: appearance repaints touch every attribute but are not edits.
    func testThemeAndFontRepaintsNeitherAskNorMarkEdited() throws {
        let (doc, tv, prompts) = try openInWindow(lossy)
        tv.applyColors(text: .white, cursor: .white, selection: .darkGray)
        tv.applyFont(size: 24, lineHeightMultiple: 1.4)
        spinRunLoop()

        XCTAssertEqual(prompts.count, 0)
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertTrue(doc.isProtected)
    }

    /// Kill-line edits the storage without the change contract, so it skips
    /// the gate until step A7. The write refusal still keeps the file safe.
    func testKillLineSkipsTheGateButTheFileStaysSafe() throws {
        let (doc, url) = try openFile(lossy)
        let original = try Data(contentsOf: url)
        let prompts = Prompts(answer: .cancel)
        doc.askBeforeEditingProtected = { _, choose in prompts.count += 1; choose(.cancel) }
        let suite = "test-protect-keybindings"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let tv = ZenTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textStorage: doc.textStorage)
        tv.delegate = doc
        tv.keybindingStore = KeybindingStore(defaults: defaults)
        doc.editor = tv

        tv.setSelectedRange(NSRange(location: 3, length: 0))
        chord(tv, "k", keyCode: 40, [.control])

        XCTAssertEqual(prompts.count, 0, "documents today's bypass; A7 routes kill-line through the gate")
        XCTAssertEqual(doc.textStorage.string, "see")
        XCTAssertNotNil(save(doc, to: url, .autosaveInPlaceOperation))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    // MARK: - Duplicate

    /// A duplicate holds what the original shows, is untitled, unprotected,
    /// and never asks. NSDocument copies it into the temporary folder's
    /// Autosave Information (measured: `$TMPDIR`, not ~/Library); teardown
    /// deletes the copy.
    func testDuplicateHoldsTheShownContentUnprotected() throws {
        let (doc, _) = try openFile(lossy)
        let copy = try XCTUnwrap(doc.duplicate() as? WhitespaceDocument)
        addTeardownBlock { @MainActor in
            if let autosaved = copy.autosavedContentsFileURL { try? FileManager.default.removeItem(at: autosaved) }
            copy.close()
        }

        XCTAssertEqual(copy.runs, doc.runs)
        XCTAssertFalse(copy.isProtected)
        XCTAssertNil(copy.fileURL)
        XCTAssertTrue(doc.isProtected, "the original stays protected")
    }
}

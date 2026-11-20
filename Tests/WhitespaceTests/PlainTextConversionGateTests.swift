// Tests/WhitespaceTests/PlainTextConversionGateTests.swift
import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import Whitespace

/// The flatten warning asks before a user Save or Save As to plain text, never
/// for an autosave, and the save it holds goes on to write the chosen file.
///
/// Documents are opened from temporary files and closed in teardown; see
/// `WhitespaceDocumentShellTests` for why.
@MainActor
final class PlainTextConversionGateTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test-conversion-gate")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test-conversion-gate")
        super.tearDown()
    }

    private var markdown: UTType { WhitespaceDocument.markdownType }
    private let formatted = [
        StyledRun(text: "plain ", bold: false, italic: false),
        StyledRun(text: "loud", bold: true, italic: false),
    ]
    private let plain = [StyledRun(text: "just words", bold: false, italic: false)]

    // MARK: - The decision

    func testApprovalNeededWhenFormattingWouldFlatten() {
        XCTAssertTrue(PlainTextConversionGate.needsApproval(runs: formatted, defaults: defaults))
    }

    func testNoApprovalNeededWithoutFormatting() {
        XCTAssertFalse(PlainTextConversionGate.needsApproval(runs: plain, defaults: defaults))
    }

    func testSuppressionSilencesTheWarning() {
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        XCTAssertFalse(PlainTextConversionGate.needsApproval(runs: formatted, defaults: defaults))
    }

    /// Every save operation AppKit has, so a new one cannot slip in as asking.
    func testOnlySaveAndSaveAsAsk() {
        let expected: [(NSDocument.SaveOperationType, Bool)] = [
            (.saveOperation, true),
            (.saveAsOperation, true),
            (.saveToOperation, false),
            (.autosaveInPlaceOperation, false),
            (.autosaveElsewhereOperation, false),
            (.autosaveAsOperation, false),
        ]
        for (operation, asks) in expected {
            XCTAssertEqual(
                PlainTextConversionGate.shouldAsk(before: operation, to: .plainText, runs: formatted, defaults: defaults),
                asks, "operation \(operation.rawValue)")
        }
    }

    func testMarkdownNeverAsks() {
        for operation in [NSDocument.SaveOperationType.saveOperation, .saveAsOperation] {
            XCTAssertFalse(PlainTextConversionGate.shouldAsk(before: operation, to: markdown,
                                                             runs: formatted, defaults: defaults))
        }
    }

    func testUnformattedOrSuppressedNeverAsks() {
        XCTAssertFalse(PlainTextConversionGate.shouldAsk(before: .saveAsOperation, to: .plainText,
                                                         runs: plain, defaults: defaults))
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        XCTAssertFalse(PlainTextConversionGate.shouldAsk(before: .saveAsOperation, to: .plainText,
                                                         runs: formatted, defaults: defaults))
    }

    // MARK: - The save, through NSDocument
    //
    // The old gate passed every decision test while writing nothing at all: it
    // aborted the save and tried to resume with `save:`, which targets the
    // document's existing URL and is a no-op on a clean document. These drive
    // the real save and check the bytes on disk.

    private func tempURL(_ ext: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-\(UUID().uuidString).\(ext)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    final class Prompts {
        var count = 0
        var answer: Bool
        init(answer: Bool) { self.answer = answer }
    }

    /// A clean document read from a markdown file, its warning replaced by a
    /// recorder that answers `answer`.
    private func openMarkdown(_ contents: String = "plain **loud**", answer: Bool) throws
        -> (WhitespaceDocument, URL, Prompts) {
        let url = tempURL("md")
        try Data(contents.utf8).write(to: url)
        let doc = try WhitespaceDocument(contentsOf: url, ofType: markdown.identifier)
        addTeardownBlock { @MainActor in doc.close() }
        let prompts = Prompts(answer: answer)
        doc.conversionDefaults = defaults
        doc.askBeforeFlattening = { _, _, choose in prompts.count += 1; choose(prompts.answer) }
        return (doc, url, prompts)
    }

    /// Runs one save and reports every completion it received.
    private func save(_ doc: WhitespaceDocument, to url: URL, as type: UTType,
                      _ operation: NSDocument.SaveOperationType) -> [Error?] {
        var results: [Error?] = []
        let done = expectation(description: "save finished")
        doc.save(to: url, ofType: type.identifier, for: operation) { error in
            results.append(error)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        spinRunLoop()
        return results
    }

    func testSaveAnywayWritesFlattenedBytesToTheChosenFile() throws {
        let (doc, original, prompts) = try openMarkdown(answer: true)
        XCTAssertFalse(doc.isDocumentEdited, "a clean document: the case the old resume path dropped")
        let target = tempURL("txt")

        let results = save(doc, to: target, as: .plainText, .saveAsOperation)

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results.first ?? nil)
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "plain loud")
        XCTAssertEqual(doc.fileURL, target)
        XCTAssertEqual(doc.fileType, UTType.plainText.identifier)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "plain **loud**")
    }

    func testCancelWritesNothingAndKeepsTheDocumentWhereItWas() throws {
        let (doc, original, prompts) = try openMarkdown(answer: false)
        let target = tempURL("txt")

        let results = save(doc, to: target, as: .plainText, .saveAsOperation)

        XCTAssertEqual(results.count, 1, "the held save must end exactly once")
        XCTAssertEqual((results.first as? CocoaError)?.code, .userCancelled,
                       "cancel ends quietly, without an error sheet")
        XCTAssertEqual(prompts.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(doc.fileURL, original)
        XCTAssertEqual(doc.fileType, markdown.identifier)
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), formatted, "nothing flattened on screen")
    }

    func testAutosaveNeverAsks() throws {
        for operation in [NSDocument.SaveOperationType.autosaveElsewhereOperation, .autosaveAsOperation,
                          .saveToOperation] {
            let (doc, _, prompts) = try openMarkdown(answer: false)
            let target = tempURL("txt")
            XCTAssertNil(save(doc, to: target, as: .plainText, operation).first ?? nil, "\(operation.rawValue)")
            XCTAssertEqual(prompts.count, 0, "\(operation.rawValue)")
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "plain loud", "\(operation.rawValue)")
        }
    }

    func testMarkdownSaveDoesNotAsk() throws {
        let (doc, url, prompts) = try openMarkdown(answer: false)
        XCTAssertNil(save(doc, to: url, as: markdown, .saveOperation).first ?? nil)
        XCTAssertEqual(prompts.count, 0)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "plain **loud**")
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), formatted, "markdown keeps its formatting")
    }

    func testSuppressedSaveWritesWithoutAsking() throws {
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        let (doc, _, prompts) = try openMarkdown(answer: false)
        let target = tempURL("txt")
        XCTAssertNil(save(doc, to: target, as: .plainText, .saveAsOperation).first ?? nil)
        XCTAssertEqual(prompts.count, 0)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "plain loud")
    }

    // MARK: - After Save Anyway

    func testSaveAnywayDropsFormattingFromTheScreenAndStaysClean() throws {
        let (doc, _, _) = try openMarkdown(answer: true)
        XCTAssertNil(save(doc, to: tempURL("txt"), as: .plainText, .saveAsOperation).first ?? nil)

        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), [StyledRun(text: "plain loud", bold: false, italic: false)])
        XCTAssertFalse(doc.isDocumentEdited, "the storage now matches its file")
        XCTAssertEqual(doc.undoManager?.canUndo, false, "dropping formatting is not an edit")
    }

    /// The bug on `main` until this change: the storage kept its bold, so the
    /// next autosave raised the warning again.
    func testLaterSavesDoNotAskAgain() throws {
        let (doc, _, prompts) = try openMarkdown(answer: true)
        let target = tempURL("txt")
        XCTAssertNil(save(doc, to: target, as: .plainText, .saveAsOperation).first ?? nil)
        XCTAssertNil(save(doc, to: target, as: .plainText, .autosaveInPlaceOperation).first ?? nil)
        XCTAssertNil(save(doc, to: target, as: .plainText, .saveOperation).first ?? nil)
        XCTAssertEqual(prompts.count, 1)
    }

    /// Characterization, not a wish: the flatten keeps the undo stack, so
    /// undoing a deletion made before the save brings that text back bold.
    /// Autosave writes it flattened without asking; the next ⌘S asks again,
    /// as for any formatted content, and drops the bold. If this starts
    /// failing, the undo behaviour changed: update the test and §2.
    func testUndoCanBringBoldBackAutosaveStaysQuietSaveAsks() throws {
        let (doc, _, prompts) = try openMarkdown("**loud quiet**", answer: true)
        doc.makeWindowControllers()
        let window = try XCTUnwrap(doc.windowControllers.first?.window)
        window.contentView?.layoutSubtreeIfNeeded()
        spinRunLoop()
        let editor = try XCTUnwrap(doc.editor)
        let undo = try XCTUnwrap(doc.undoManager)

        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.setSelectedRange(NSRange(location: 4, length: 6))
        editor.delete(nil)
        undo.endUndoGrouping()
        undo.groupsByEvent = true
        spinRunLoop()
        XCTAssertEqual(doc.textStorage.string, "loud")

        let target = tempURL("txt")
        XCTAssertNil(save(doc, to: target, as: .plainText, .saveAsOperation).first ?? nil)
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), [StyledRun(text: "loud", bold: false, italic: false)])

        undo.undo()
        spinRunLoop()
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), [
            StyledRun(text: "loud", bold: false, italic: false),
            StyledRun(text: " quiet", bold: true, italic: false),
        ])

        XCTAssertNil(save(doc, to: target, as: .plainText, .autosaveInPlaceOperation).first ?? nil)
        XCTAssertEqual(prompts.count, 1, "autosave never asks")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "loud quiet")

        XCTAssertNil(save(doc, to: target, as: .plainText, .saveOperation).first ?? nil)
        XCTAssertEqual(prompts.count, 2, "a user Save with bold back asks again")
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), [StyledRun(text: "loud quiet", bold: false, italic: false)])
    }

    func testAFailedSaveKeepsTheFormatting() throws {
        let (doc, _, _) = try openMarkdown(answer: true)
        let unwritable = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/out.txt")
        XCTAssertNotNil(save(doc, to: unwritable, as: .plainText, .saveAsOperation).first ?? nil)
        XCTAssertEqual(StyledRun.runs(in: doc.textStorage), formatted)
    }
}

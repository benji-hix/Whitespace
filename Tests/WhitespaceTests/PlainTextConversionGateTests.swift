// Tests/WhitespaceTests/PlainTextConversionGateTests.swift
import XCTest
import UniformTypeIdentifiers
@testable import Whitespace

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

    /// Unformatted content must never reach the dialog.
    func testUnformattedContentIsNeverAsked() {
        var asked = false
        let allowed = PlainTextConversionGate.approveFlattening(
            runs: plain, defaults: defaults, ask: { _ in asked = true; return false }
        )
        XCTAssertTrue(allowed)
        XCTAssertFalse(asked, "plain content should not raise the dialog")
    }

    func testSuppressedContentIsNeverAsked() {
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        var asked = false
        let allowed = PlainTextConversionGate.approveFlattening(
            runs: formatted, defaults: defaults, ask: { _ in asked = true; return false }
        )
        XCTAssertTrue(allowed)
        XCTAssertFalse(asked, "a suppressed warning should not raise the dialog")
    }

    // MARK: - The write actually reaching disk
    //
    // The old gate passed every decision test above while writing nothing at
    // all: it aborted the save and tried to resume with `save:`, which targets
    // the document's existing URL and is a no-op on a clean document. Decision
    // coverage cannot see that. These drive the write path and check the bytes.

    private func writeToTemp(_ data: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gate-\(UUID().uuidString).txt")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testSaveAnywayWritesFlattenedBytesToDisk() throws {
        let doc = makeDocument(runs: formatted, type: .plainText)
        let data = try doc.approvedData(for: .plainText, defaults: defaults, ask: { _ in true })

        let url = try writeToTemp(data)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "plain loud", "approved save must land flattened bytes on disk")
        XCTAssertFalse(onDisk.contains("**"), "plain text must not carry markdown markers")
    }

    func testCancelAbortsTheSaveAndWritesNothing() {
        let doc = makeDocument(runs: formatted, type: .plainText)
        XCTAssertThrowsError(
            try doc.approvedData(for: .plainText, defaults: defaults, ask: { _ in false })
        ) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .userCancelled,
                           "cancel must abort quietly, not surface an error sheet")
        }
    }

    /// Markdown keeps its formatting, so it must write without ever asking.
    func testMarkdownWriteIsNotGated() throws {
        let doc = makeDocument(runs: formatted, type: WhitespaceDocument.markdownType)
        var asked = false
        let data = try doc.approvedData(
            for: WhitespaceDocument.markdownType,
            defaults: defaults,
            ask: { _ in asked = true; return false }
        )
        XCTAssertFalse(asked, "a markdown save must never raise the flatten warning")
        XCTAssertEqual(String(data: data, encoding: .utf8), "plain **loud**")
    }

    func testSuppressedSaveWritesWithoutAsking() throws {
        defaults.set(true, forKey: PlainTextConversionGate.suppressKey)
        let doc = makeDocument(runs: formatted, type: .plainText)
        let data = try doc.approvedData(for: .plainText, defaults: defaults, ask: { _ in false })
        XCTAssertEqual(String(data: data, encoding: .utf8), "plain loud")
    }
}
